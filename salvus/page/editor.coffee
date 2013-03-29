##################################################
# Editor for files in a project
##################################################

async = require('async')

message = require('message')

{salvus_client} = require('salvus_client')
{EventEmitter}  = require('events')
{alert_message} = require('alerts')

{IS_MOBILE} = require("feature")

misc = require('misc')
# TODO: undo doing the import below -- just use misc.[stuff] is more readable.
{copy, trunc, from_json, to_json, keys, defaults, required, filename_extension, len, path_split, uuid} = require('misc')

syncdoc = require('syncdoc')

top_navbar =  $(".salvus-top_navbar")

codemirror_associations =
    c      : 'text/x-c'
    'c++'  : 'text/x-c++src'
    cpp    : 'text/x-c++src'
    cc     : 'text/x-c++src'
    csharp : 'text/x-csharp'
    'c#'   : 'text/x-csharp'
    java   : 'text/x-java'
    coffee : 'coffeescript'
    php    : 'php'
    py     : 'python'
    pyx    : 'python'
    css    : 'css'
    diff   : 'diff'
    ecl    : 'ecl'
    h      : 'text/x-c++hdr'
    html   : 'htmlmixed'
    js     : 'javascript'
    lua    : 'lua'
    md     : 'markdown'
    r      : 'r'
    rst    : 'rst'
    sage   : 'python'
    scala  : 'text/x-scala'
    sh     : 'shell'
    spyx   : 'python'
    sql    : 'mysql'
    txt    : 'text'
    tex    : 'stex'
    xml    : 'xml'
    yaml   : 'yaml'
    ''     : 'text'

file_associations = exports.file_associations = {}
for ext, mode of codemirror_associations
    file_associations[ext] =
        editor : 'codemirror'
        opts   : {mode:mode}

file_associations['tex'] =
    editor : 'latex'
    icon   : 'icon-edit'
    opts   : {mode:'stex', indent_unit:4, tab_size:4}

file_associations['html'] =
    editor : 'codemirror'
    icon   : 'icon-edit'
    opts   : {mode:'htmlmixed', indent_unit:4, tab_size:4}

file_associations['css'] =
    editor : 'codemirror'
    icon   : 'icon-edit'
    opts   : {mode:'css', indent_unit:4, tab_size:4}

file_associations['salvus-terminal'] =
    editor : 'terminal'
    icon   : 'icon-credit-card'
    opts   : {}

file_associations['salvus-worksheet'] =
    editor : 'worksheet'
    icon   : 'icon-list-ul'
    opts   : {}

file_associations['salvus-spreadsheet'] =
    editor : 'spreadsheet'
    opts   : {}

file_associations['salvus-slideshow'] =
    editor : 'slideshow'
    opts   : {}

for ext in ['png', 'jpg', 'gif', 'svg']
    file_associations[ext] =
        editor : 'image'
        opts   : {}

file_associations['pdf'] =
    editor : 'pdf'
    opts   : {}

# Given a text file (defined by content), try to guess
# what the extension should be.
guess_file_extension_type = (content) ->
    content = $.trim(content)
    i = content.indexOf('\n')
    first_line = content.slice(0,i).toLowerCase()
    if first_line.slice(0,2) == '#!'
        # A script.  What kind?
        if first_line.indexOf('python') != -1
            return 'py'
        if first_line.indexOf('bash') != -1 or first_line.indexOf('sh') != -1
            return 'sh'
    if first_line.indexOf('html') != -1
        return 'html'
    if first_line.indexOf('/*') != -1 or first_line.indexOf('//') != -1   # kind of a stretch
        return 'c++'
    return undefined

SEP = "\uFE10"

_local_storage_prefix = (project_id, filename, key) ->
    s = project_id
    if filename?
        s += filename + SEP
    if key?
        s += key
    return s
#
# Set or get something about a project from local storage:
#
#    local_storage(project_id):  returns everything known about this project.
#    local_storage(project_id, filename):  get everything about given filename in project
#    local_storage(project_id, filename, key):  get value of key for given filename in project
#    local_storage(project_id, filename, key, value):   set value of key
#
# In all cases, returns undefined if localStorage is not supported in this browser.
#

local_storage_delete = exports.local_storage_delete = (project_id, filename, key) ->
    storage = window.localStorage
    if storage?
        prefix = _local_storage_prefix(project_id, filename, key)
        n = prefix.length
        for k, v of storage
            if k.slice(0,n) == prefix
                delete storage[k]

local_storage = exports.local_storage = (project_id, filename, key, value) ->
    storage = window.localStorage
    if storage?
        prefix = _local_storage_prefix(project_id, filename, key)
        n = prefix.length
        if filename?
            if key?
                if value?
                    storage[prefix] = misc.to_json(value)
                else
                    x = storage[prefix]
                    if not x?
                        return x
                    else
                        return misc.from_json(x)
            else
                # Everything about a given filename
                obj = {}
                for k, v of storage
                    if k.slice(0,n) == prefix
                        obj[k.split(SEP)[1]] = v
                return obj
        else
            # Everything about project
            obj = {}
            for k, v of storage
                if k.slice(0,n) == prefix
                    x = k.slice(n)
                    z = x.split(SEP)
                    filename = z[0]
                    key = z[1]
                    if not obj[filename]?
                        obj[filename] = {}
                    obj[filename][key] = v
            return obj

templates = $("#salvus-editor-templates")

class exports.Editor
    constructor: (opts) ->
        opts = defaults opts,
            project_page   : required
            initial_files : undefined # if given, attempt to open these files on creation
            counter       : undefined # if given, is a jQuery set of DOM objs to set to the number of open files

        @counter = opts.counter

        @project_page  = opts.project_page
        @project_path = opts.project_page.project.location.path
        @project_id = opts.project_page.project.project_id
        @element = templates.find(".salvus-editor").clone().show()
        @nav_tabs = @element.find(".nav-pills")

        @tabs = {}   # filename:{useful stuff}

        @init_openfile_search()
        @init_close_all_tabs_button()

        @element.find("a[href=#save-all]").click () =>
            @save()
            return false

        if opts.initial_files?
            for filename in opts.initial_files
                @open(filename)

        # TODO -- maybe neither of these get freed properly when project is closed.
        # Also -- it's a bit weird to call them even if project not currently visible.
        # Add resize trigger
        $(window).resize(@_window_resize_while_editing)

        $(document).on 'keyup', (ev) =>
            if (ev.metaKey or ev.ctrlKey) and ev.keyCode == 79
                @focus()
                return false


    focus: () =>
        @element.find(".salvus-editor-search-openfiles-input").focus()
        @hide_editor_content()

    hide_editor_content: () =>
        @_editor_content_visible = false
        @element.find(".salvus-editor-content").hide()

    show_editor_content: () =>
        @_editor_content_visible = true
        @element.find(".salvus-editor-content").show()
        # temporary / ugly
        for tab in @project_page.tabs
            tab.label.removeClass('active')


    # Used for resizing editor windows.
    editor_top_position: () =>
        return @element.find(".salvus-editor-content").position().top

    _window_resize_while_editing: () =>
        if not @active_tab? or not @_editor_content_visible
            return
        @active_tab.editor().show()

    init_close_all_tabs_button: () =>
        @element.find("a[href=#close-all-tabs]").click () =>
            v = []
            for filename, tab of @tabs
                @close(filename)
                v.push(filename)
            undo = @element.find("a[href=#undo-close-all-tabs]")
            undo.stop().show().animate(opacity:100).fadeOut(duration:60000).click () =>
                undo.hide()
                for filename in v
                    if not @tabs[filename]?
                        @create_tab(filename:filename)
                return false
            alert_message(type:'info', message:"Closed all recently opened files.")
            return false

    init_openfile_search: () =>
        search_box = @element.find(".salvus-editor-search-openfiles-input")
        include = 'active' #salvus-editor-openfile-included-in-search'
        exclude = 'salvus-editor-openfile-excluded-from-search'
        search_box.focus () =>
            search_box.select()

        search_box.keyup (event) =>
            @active_tab?.editor().hide()

            if (event.metaKey or event.ctrlKey) and event.keyCode == 79     # control-o
                @project_page.display_tab("project-new-file")
                return false

            if event.keyCode == 27  and @active_tab? # escape - open last viewed tab
                @display_tab(@active_tab.filename)
                return

            v = $.trim(search_box.val()).toLowerCase()
            if v == ""
                for filename, tab of @tabs
                    tab.link.removeClass(include)
                    tab.link.removeClass(exclude)
                match = (s) -> true
            else
                terms = v.split(' ')
                match = (s) ->
                    s = s.toLowerCase()
                    for t in terms
                        if s.indexOf(t) == -1
                            return false
                    return true

            first = true

            for link in @nav_tabs.children()
                tab = $(link).data('tab')
                filename = tab.filename
                if match(filename)
                    if first and event.keyCode == 13 # enter -- select first match (if any)
                        @display_tab(filename)
                        first = false
                    if v != ""
                        tab.link.addClass(include); tab.link.removeClass(exclude)
                else
                    if v != ""
                        tab.link.addClass(exclude); tab.link.removeClass(include)

    update_counter: () =>
        if @counter?
            @counter.text(len(@tabs))

    open: (filename) =>
        if not @tabs[filename]?   # if it is defined, then nothing to do -- file already loaded
            @tabs[filename] = @create_tab(filename:filename)

    file_options: (filename, content) =>   # content may be undefined
        ext = filename_extension(filename)
        if not ext? and content?   # no recognized extension, but have contents
            ext = guess_file_extension_type(content)
        x = file_associations[ext]
        if not x?
            x = file_associations['']
        return x

    create_tab: (opts) =>
        opts = defaults opts,
            filename     : required
            content      : undefined

        filename = opts.filename
        content = opts.content
        opts0 = @file_options(filename, content)
        extra_opts = copy(opts0.opts)
        if opts.session_uuid?
            extra_opts.session_uuid = opts.session_uuid

        local_storage(@project_id, filename, "auto_open", true)

        link = templates.find(".salvus-editor-filename-pill").clone().show()
        link_filename = link.find(".salvus-editor-tab-filename")
        link_filename.text(trunc(filename,64))

        link.find(".salvus-editor-close-button-x").click () =>
            if ignore_clicks
                return false
            @close(filename)

        containing_path = misc.path_split(filename).head
        ignore_clicks = false
        link.find("a").click () =>
            if ignore_clicks
                return false
            @display_tab(link_filename.text())
            @project_page.set_current_path(containing_path)

        create_editor_opts =
            editor_name : opts0.editor
            filename    : filename
            content     : content
            extra_opts  : extra_opts

        editor = undefined
        @tabs[filename] =
            link     : link
            filename : filename
            editor   : () =>
                if editor?
                    return editor
                else
                    editor = @create_editor(create_editor_opts)
                    @element.find(".salvus-editor-content").append(editor.element.hide())
                    @create_opened_file_tab(filename)
                    return editor
            hide_editor: () -> editor?.hide()

        link.data('tab', @tabs[filename])
        link.draggable
            zIndex      : 1000
            #containment : @element
            stop        : () =>
                ignore_clicks = true
                setTimeout( (() -> ignore_clicks=false), 100)


        @nav_tabs.append(link)

        @update_counter()
        return @tabs[filename]

    create_editor: (opts) =>
        {editor_name, filename, content, extra_opts} = defaults opts,
            editor_name : required
            filename    : required
            content     : required
            extra_opts  : required
        #console.log('create_editor: ', opts)
        # Some of the editors below might get the content later and will call @file_options again then.
        switch editor_name
            # codemirror is the default... TODO: JSON, since I have that jsoneditor plugin.
            when 'codemirror', undefined
                editor = codemirror_session_editor(@, filename, extra_opts)
            when 'terminal'
                editor = new Terminal(@, filename, content, extra_opts)
            when 'worksheet'
                editor = new Worksheet(@, filename, content, extra_opts)
            when 'spreadsheet'
                editor = new Spreadsheet(@, filename, content, extra_opts)
            when 'slideshow'
                editor = new Slideshow(@, filename, content, extra_opts)
            when 'image'
                editor = new Image(@, filename, content, extra_opts)
            when 'latex'
                editor = new LatexEditor(@, filename, content, extra_opts)
            when 'pdf'
                editor = new PDF_Preview(@, filename, content, extra_opts)
            else
                throw("Unknown editor type '#{editor_name}'")

        return editor

    create_opened_file_tab: (filename) =>
        link = templates.find(".salvus-editor-filename-pill").clone()

        link_filename = link.find(".salvus-editor-tab-filename")
        link_filename.text(trunc(filename,32))

        link.find(".salvus-editor-close-button-x").click () =>
            if ignore_clicks
                return false
            link.remove()
            return false

        containing_path = misc.path_split(filename).head
        ignore_clicks = false
        link.find("a").click () =>
            if ignore_clicks
                return false
            @display_tab(filename)
            @project_page.container.find(".project-pages").children().removeClass('active')
            link.addClass('active')
            @project_page.set_current_path(containing_path)
            return false

        @project_page.container.find(".project-search-menu-item").after(link)
        link.draggable
            zIndex      : 1000
            containment : "parent"
            stop        : () =>
                ignore_clicks = true
                setTimeout( (() -> ignore_clicks=false), 100)

    # Close this tab.
    close: (filename) =>
        tab = @tabs[filename]
        if not tab? # nothing to do -- tab isn't opened anymore
            return

        # Do not auto_open this file on this browser next time.
        local_storage_delete(@project_id, filename, "auto_open")

        # Disconnect from remote session (if relevant)
        tab.editor().disconnect_from_session()
        tab.link.remove()
        tab.editor().remove()
        delete @tabs[filename]
        @update_counter()

        # Display some other tab.
        #names = keys(@tabs)
        #if names.length > 0
            # select new tab
        #    @display_tab(names[0])

    # Reload content of this tab.  Warn user if this will result in changes.
    reload: (filename) =>
        tab = @tabs[filename]
        if not tab? # nothing to do
            return
        salvus_client.read_text_file_from_project
            project_id : @project_id
            timeout    : 5
            path       : filename
            cb         : (err, mesg) =>
                if err
                    alert_message(type:"error", message:"Communications issue loading new version of #{filename} -- #{err}")
                else if mesg.event == 'error'
                    alert_message(type:"error", message:"Error loading new version of #{filename} -- #{to_json(mesg.error)}")
                else
                    current_content = tab.editor().val()
                    new_content = mesg.content
                    if current_content != new_content
                        @warn_user filename, (proceed) =>
                            if proceed
                                tab.editor().val(new_content)

    # Warn user about unsaved changes (modal)
    warn_user: (filename, cb) =>
        cb(true)

    # Make the give tab active.
    display_tab: (filename) =>
        if not @tabs[filename]?
            return
        @show_editor_content()
        prev_active_tab = @active_tab
        for name, tab of @tabs
            if name == filename
                @active_tab = tab
                ed = tab.editor()
                ed.show()
                setTimeout((() -> ed.show(); ed.focus()), 200)
                @element.find(".btn-group").children().removeClass('disabled')
            else
                tab.hide_editor()

        if prev_active_tab? and prev_active_tab.filename != @active_tab.filename and @tabs[prev_active_tab.filename]?   # ensure is still open!
            @nav_tabs.prepend(prev_active_tab.link)

    add_tab_to_navbar: (filename) =>
        navbar = require('top_navbar').top_navbar
        tab = @tabs[filename]
        if not tab?
            return
        id = @project_id + filename
        if not navbar.pages[id]?
            navbar.add_page
                id     : id
                label  : misc.path_split(filename).tail
                onshow : () =>
                    navbar.switch_to_page(@project_id)
                    @display_tab(filename)
                    navbar.make_button_active(id)

    onshow: () =>  # should be called when the editor is shown.
        #if @active_tab?
        #    @display_tab(@active_tab.filename)
        @element.find(".salvus-editor-search-openfiles-input").focus()

    # Save the file to disk/repo
    save: (filename, cb) =>       # cb(err)
        if not filename?  # if filename not given, save all files
            tasks = []
            for filename in keys(@tabs)
                f = (c) =>
                    @save(arguments.callee.filename, c)
                f.filename = filename
                tasks.push(f)
            async.parallel(tasks, cb)
            return

        tab = @tabs[filename]
        if not tab?
            cb?()
            return

        if not tab.editor().has_unsaved_changes()
            # nothing to save
            cb?()
            return

        tab.editor().save(cb)

    change_tab_filename: (old_filename, new_filename) =>
        tab = @tabs[old_filename]
        if not tab?
            # TODO -- fail silently or this?
            alert_message(type:"error", message:"change_tab_filename (bug): attempt to change #{old_filename} to #{new_filename}, but there is no tab #{old_filename}")
            return
        tab.filename = new_filename
        tab.link.find(".salvus-editor-tab-filename").text(new_filename)
        delete @tabs[old_filename]
        @tabs[new_filename] = tab


###############################################
# Abstract base class for editors
###############################################
# Derived classes must:
#    (1) implement the _get and _set methods
#    (2) show/hide/remove
#
# Events ensure that *all* users editor the same file see the same
# thing (synchronized).
#

class FileEditor extends EventEmitter
    constructor: (@editor, @filename, content, opts) ->
        @val(content)

    init_autosave: () =>
        if @_autosave_interval?
            # This function can safely be called again to *adjust* the
            # autosave interval, in case user changes the settings.
            clearInterval(@_autosave_interval)

        # Use the most recent autosave value.
        autosave = require('account').account_settings.settings.autosave
        if autosave
            save_if_changed = () =>
                if not @editor.tabs[@filename]?
                    # don't autosave anymore if the doc is closed
                    clearInterval(@_autosave_interval)
                    return
                if @has_unsaved_changes()
                    if @click_save_button?
                        # nice gui feedback
                        @click_save_button()
                    else
                        @save()
            @_autosave_interval = setInterval(save_if_changed, autosave * 1000)

    val: (content) =>
        if not content?
            # If content not defined, returns current value.
            return @_get()
        else
            # If content is defined, sets value.
            @_set(content)

    # has_unsaved_changes() returns the state, where true means that
    # there are unsaved changed.  To set the state, do
    # has_unsaved_changes(true or false).
    has_unsaved_changes: (val) =>
        if not val?
            return @_has_unsaved_changes
        else
            @_has_unsaved_changes = val

    focus: () => # TODO in derived class

    _get: () =>
        throw("TODO: implement _get in derived class")

    _set: (content) =>
        throw("TODO: implement _set in derived class")

    restore_cursor_position : () =>
        # implement in a derived class if you need this

    disconnect_from_session : (cb) =>
        # implement in a derived class if you need this

    local_storage: (key, value) =>
        return local_storage(@editor.project_id, @filename, key, value)

    show: () =>
        @element.show()

    hide: () =>
        @element.hide()

    remove: () =>
        @element.remove()

    terminate_session: () =>
        # If some backend session on a remote machine is serving this session, terminate it.

    save: (cb) =>
        content = @val()
        if not content?
            # do not overwrite file in case editor isn't initialized
            alert_message(type:"error", message:"Editor of '#{filename}' not initialized, so nothing to save.")
            cb?()
            return

        salvus_client.write_text_file_to_project
            project_id : @editor.project_id
            timeout    : 10
            path       : @filename
            content    : content
            cb         : (err, mesg) =>
                # TODO -- on error, we *might* consider saving to localStorage...
                if err
                    alert_message(type:"error", message:"Communications issue saving #{filename} -- #{err}")
                    cb?(err)
                else if mesg.event == 'error'
                    alert_message(type:"error", message:"Error saving #{filename} -- #{to_json(mesg.error)}")
                    cb?(mesg.error)
                else
                    cb?()

###############################################
# Codemirror-based File Editor
###############################################
class CodeMirrorEditor extends FileEditor
    constructor: (@editor, @filename, content, opts) ->
        opts = @opts = defaults opts,
            mode              : required
            delete_trailing_whitespace : true   # delete all trailing whitespace on save
            line_numbers      : true
            indent_unit       : 4
            tab_size          : 4
            smart_indent      : true
            electric_chars    : true
            undo_depth        : 1000
            match_brackets    : true
            line_wrapping     : true
            theme             : "solarized"  # see static/codemirror*/themes or head.html
            # I'm making the times below very small for now.  If we have to adjust these to reduce load, due to lack
            # of capacity, then we will.  Or, due to lack of optimization (e.g., for big documents). These parameters
            # below would break editing a huge file right now, due to slowness of applying a patch to a codemirror editor.

            cursor_interval   : 150   # minimum time (in ms) between sending cursor position info to hub -- used in sync version
            sync_interval     : 150   # minimum time (in ms) between synchronizing text with hub. -- used in sync version below

        @project_id = @editor.project_id
        @element = templates.find(".salvus-editor-codemirror").clone()
        @element.find(".salvus-editor-codemirror-filename").text(@filename)
        elt = @element.find(".salvus-editor-codemirror-input-box").find("textarea")
        elt.text(content)
        @codemirror = CodeMirror.fromTextArea elt[0],
            firstLineNumber : 1
            autofocus       : false
            mode            : opts.mode
            lineNumbers     : opts.line_numbers
            indentUnit      : opts.indent_unit
            tabSize         : opts.tab_size
            smartIndent     : opts.smart_indent
            electricChars   : opts.electric_chars
            undoDepth       : opts.undo_depth
            matchBrackets   : opts.match_brackets
            theme           : opts.theme
            lineWrapping    : opts.line_wrapping
            extraKeys       :
                "Shift-Enter"  : (editor)   => @click_save_button()
                "Ctrl-S"       : (editor)   => @click_save_button()
                "Cmd-S"        : (editor)   => @click_save_button()
                "Shift-Tab"    : (editor)   => editor.unindent_selection()
                "Ctrl-Space"  : "indentAuto"
                "Tab"          : (editor)   =>
                    c = editor.getCursor(); d = editor.getCursor(true)
                    if c.line==d.line and c.ch == d.ch
                        editor.tab_as_space()
                    else
                        CodeMirror.commands.defaultTab(editor)
        @init_save_button()
        @init_change_event()
        #@element.find("a[href=#topbar]").click () =>
        #    @editor.add_tab_to_navbar(@filename)
        #    return false

    init_save_button: () =>
        @save_button = @element.find("a[href=#save]").click(@click_save_button)
        @save_button.find(".spinner").hide()

    click_save_button: () =>
        if not @save_button.hasClass('disabled')
            @save_button.find('span').text("Saving...")
            spin = setTimeout((() => @save_button.find(".spinner").show()), 100)
            @editor.save @filename, (err) =>
                clearTimeout(spin)
                @save_button.find(".spinner").hide()
                @save_button.find('span').text('Save')
                if not err
                    @save_button.addClass('disabled')
                    @has_unsaved_changes(false)
        return false

    init_change_event: () =>
        @codemirror.on 'change', (instance, changeObj) =>
            @has_unsaved_changes(true)
            @save_button.removeClass('disabled')

    _get: () =>
        return @codemirror.getValue()

    _set: (content) =>
        {from} = @codemirror.getViewport()
        @codemirror.setValue(content)
        @codemirror.scrollIntoView(from)
        # even better, if available
        @restore_cursor_position()

    restore_cursor_position: () =>
        pos = @local_storage("cursor")
        if pos?
            @codemirror.setCursor(pos)
            @codemirror.scrollIntoView({line:pos.line-5, ch:0})   # todo -- would be better to center rather than a magic "5".

    show: () =>
        if not (@element? and @codemirror?)
            #console.log('skipping show because things not defined yet.')
            return

        @element.show()
        @codemirror.refresh()

        height = $(window).height()

        top = @editor.editor_top_position()
        elem_height = height - top

        button_bar_height = @element.find(".salvus-editor-codemirror-button-row").height()
        font_height = @codemirror.defaultTextHeight()

        cm_height = Math.floor((elem_height - button_bar_height)/font_height - 1) * font_height

        @element.height(elem_height).show()

        scroller = $(@codemirror.getScrollerElement())
        scroller.css('height':cm_height)

        if @_chat_is_hidden? and not @_chat_is_hidden
            width = $(window).width() - @element.find(".salvus-editor-codemirror-chat-column").width()
        else
            width = $(window).width()

        cm_wrapper = $(@codemirror.getWrapperElement())
        cm_wrapper.css
            'background-color':'#ffffe8'
            height : cm_height
            width  : width

        window.scrollTo(0, document.body.scrollHeight)
        $(".salvus-top-scroll").show()

        @codemirror.refresh()

        chat = @element.find(".salvus-editor-codemirror-chat")
        chat.height(cm_height)
        chat.width(0)
        output = chat.find(".salvus-editor-codemirror-chat-output")
        output.scrollTop(output[0].scrollHeight)

    focus: () =>
        if not @codemirror?
            return
        @show()
        if not IS_MOBILE
            @codemirror.focus()
        # @codemirror.refresh()


codemirror_session_editor = (editor, filename, extra_opts) ->
    E = new CodeMirrorEditor(editor, filename, "", extra_opts)
    # Enhance the editor with synchronized session capabilities.
    opts =
        cursor_interval : E.opts.cursor_interval
        sync_interval   : E.opts.sync_interval
    E.syncdoc = new (syncdoc.SynchronizedDocument)(E, opts)
    return E


###############################################
# LateX Editor
###############################################

# Make a temporary uuid-named directory in path.
tmp_dir = (project_id, path, cb) ->      # cb(err, directory_name)
    name = "." + uuid()   # hidden
    salvus_client.exec
        project_id : project_id
        path       : path
        command    : "mkdir"
        args       : [name]
        cb         : (err, output) =>
            if err
                cb("Problem creating temporary PDF preview path.")
            else
                cb(false, name)

remove_tmp_dir = (project_id, path, tmp_dir, cb) ->
    salvus_client.exec
        project_id : project_id
        path       : path
        command    : "rm"
        args       : ['-rf', tmp_dir]
        cb         : (err, output) =>
            cb?(err)

class PDF_Preview extends FileEditor
    # Compute single page
    constructor: (@editor, @filename, contents, opts) ->
        @element = templates.find(".salvus-editor-pdf-preview").clone()
        @spinner = @element.find(".salvus-editor-pdf-preview-spinner")

        @page_number = 1
        @density = 300  # impacts the clarity

        s = path_split(@filename)
        @path = s.head
        if @path == ''
            @path = './'
        @file = s.tail

        #@element.find("a[href=#prev]").click(@prev_page)
        #@element.find("a[href=#next]").click(@next_page)
        #@element.find("a[href=#zoom-in]").click(@zoom_in)
        #@element.find("a[href=#zoom-out]").click(@zoom_out)

        @element.css('height':$(window).height()*.8)
        @output = @element.find(".salvus-editor-pdf-preview-page")
        @update () =>
            @element.resizable(handles: "e,w,s,sw,se").on('resize', @focus)

    focus: () =>
        @output.height(@element.height())
        @output.width(@element.width())

    update: (cb) =>
        @output.height(@element.height())
        @output.width(@element.width())
        @spinner.show().spin(true)
        tmp_dir @editor.project_id, @path, (err, tmp) =>
            if err
                @spinner.hide().spin(false)
                alert_message(type:"error", message:err)
                cb?(err)
                return
            # Update the PNG's which provide a preview of the PDF
            salvus_client.exec
                project_id : @editor.project_id
                path       : @path
                command    : 'gs'
                args       : ["-dBATCH", "-dNOPAUSE",
                              "-sDEVICE=pngmono",
                              "-sOutputFile=#{tmp}/%d.png", "-r#{@density}", @file]

                timeout    : 20
                err_on_exit: false
                cb         : (err, output) =>
                    if err
                        alert_message(type:"error", message:err)
                        remove_tmp_dir(@editor.project_id, @path, tmp)
                        cb?(err)
                    else
                        i = output.stdout.indexOf("Page")
                        s = output.stdout.slice(i)
                        pages = {}
                        tasks = []
                        while s.length>4
                            i = s.indexOf('\n')
                            if i == -1
                                break
                            page_number = s.slice(5,i)
                            s = s.slice(i+1)

                            png_file = @path + "/#{tmp}/" + page_number + '.png'
                            f = (cb) =>
                                num  = arguments.callee.page_number
                                salvus_client.read_file_from_project
                                    project_id : @editor.project_id
                                    path       : arguments.callee.png_file
                                    cb         : (err, result) =>
                                        if err
                                            cb(err)
                                        else
                                            if result.url?
                                                pages[num] = result.url
                                            cb()

                            f.png_file = png_file
                            f.page_number = parseInt(page_number)
                            tasks.push(f)

                        async.parallel tasks, (err) =>
                            remove_tmp_dir(@editor.project_id, @path, tmp)
                            if err
                                alert_message(type:"error", message:"Error downloading png preview -- #{err}")
                                @spinner.spin(false).hide()
                                cb?(err)
                            else
                                if len(pages) == 0
                                    @output.html('')
                                else
                                    children = @output.children()
                                    # We replace existing pages if possible, which nicely avoids all nasty scrolling issues/crap.
                                    for n in [0...len(pages)]
                                        url = pages[n+1]
                                        if n < children.length
                                            $(children[n]).attr('src', url)
                                        else
                                            @output.append($("<img src='#{url}' class='salvus-editor-pdf-preview-image'>"))
                                    # Delete any remaining pages from before (if doc got shorter)
                                    for n in [len(pages)...children.length]
                                        $(children[n]).remove()
                                @spinner.spin(false).hide()
                                cb?()

    next_page: () =>
        @page_number += 1   # TODO: !what if last page?
        @update()

    prev_page: () =>
        if @page_number >= 2
            @page_number -= 1
            @update()

    zoom_out: () =>
        if @density >= 75
            @density -= 25
            @update()

    zoom_in: () =>
        @density += 25
        @update()

    show: () =>
        @element.show()
        @focus()

    hide: () =>
        @element.hide()


class LatexEditor extends FileEditor
    constructor: (@editor, @filename, content, opts) ->
        # The are three components:
        #     * latex_editor -- a CodeMirror editor
        #     * preview -- display the images (page forward/backward/resolution)
        #     * log -- log of latex command
        opts.mode = 'stex'

        @_current_page = 'latex_editor'
        @element = templates.find(".salvus-editor-latex").clone()

        # initialize the latex_editor
        @latex_editor = codemirror_session_editor(@editor, filename, opts)
        @element.find(".salvus-editor-latex-latex_editor").append(@latex_editor.element)

        v = path_split(@filename)
        @_path = v.head
        @_target = v.tail

        # initialize the preview
        n = @filename.length
        @preview = new PDF_Preview(@editor, @filename.slice(0,n-3)+"pdf", undefined, {})
        @element.find(".salvus-editor-latex-preview").append(@preview.element)

        # initalize the log
        @log = @element.find(".salvus-editor-latex-log")

        @_init_buttons()

        @preview.update()

    _init_buttons: () =>
        @element.find("a[href=#latex_editor]").click () =>
            @show_page('latex_editor')
            @latex_editor.focus()
            return false

        @element.find("a[href=#preview]").click () =>
            @compile_and_update()
            @show_page('preview')
            return false

        #@element.find("a[href=#log]").click () =>
            #@show_page('log')
            return false

        @element.find("a[href=#latex]").click () =>
            @show_page('log')
            @compile_and_update()
            return false

        @element.find("a[href=#pdf]").click () =>
            @download_pdf()
            return false

    click_save_button: () =>
        @latex_editor.click_save_button()

    save: (cb) =>
        @latex_editor.save(cb)

    compile_and_update: (cb) =>
        async.series([
            (cb) =>
                @editor.save(@filename, cb)
            (cb) =>
                @run_latex (err) =>
                    # latex prefers to be run twice...
                    if err
                        cb(err)
                    else
                        @run_latex(cb)

            (cb) =>
                @preview.update(cb)
        ], (err) -> cb?(err))

    _get: () =>
        return @latex_editor._get()

    _set: (content) =>
        @latex_editor._set(content)

    show: () =>
        @element?.show()
        @latex_editor?.show()

    focus: () =>
        @latex_editor?.focus()

    has_unsaved_changes: (val) =>
        return @latex_editor?.has_unsaved_changes(val)

    show_page: (name) =>
        if name == @_current_page
            return
        for n in ['latex_editor', 'preview', 'log']
            e = @element.find(".salvus-editor-latex-#{n}")
            button = @element.find("a[href=#" + n + "]")
            if n == name
                e.show()
                button.addClass('btn-primary')
            else
                e.hide()
                button.removeClass('btn-primary')
        @_current_page = name

    run_latex: (cb) =>
        @save (err) =>
            # TODO -- what about error?
            salvus_client.exec
                project_id : @editor.project_id
                path       : @_path
                command    : 'pdflatex'
                args       : ['-interaction=nonstopmode', '\\input', @_target]
                timeout    : 5
                err_on_exit : false
                cb         : (err, output) =>
                    if err
                        alert_message(type:"error", message:err)
                    else
                        @log.find("textarea").text(output.stdout + '\n\n' + output.stderr)
                        # Scroll to the bottom of the textarea
                        f = @log.find('textarea')
                        f.scrollTop(f[0].scrollHeight)

                    cb?()

    download_pdf: () =>
        # TODO: THIS replicates code in project.coffee
        salvus_client.read_file_from_project
            project_id : @editor.project_id
            path       : @filename.slice(0,@filename.length-3)+"pdf"
            cb         : (err, result) =>
                if err
                    alert_message(type:"error", message:"Error downloading PDF: #{err} -- #{misc.to_json(result)}")
                else
                    url = result.url + "&download"
                    iframe = $("<iframe>").addClass('hide').attr('src', url).appendTo($("body"))
                    setTimeout((() -> iframe.remove()), 1000)



class Terminal extends FileEditor
    constructor: (@editor, @filename, content, opts) ->
        @element = $("<div>").hide()
        salvus_client.read_text_file_from_project
            project_id : @editor.project_id
            path       : @filename
            cb         : (err, result) =>
                if err
                    alert_message(type:"error", message: "Error connecting to console server.")
                else
                    # New session
                    opts = @opts = defaults opts,
                        session_uuid : result.content
                        rows         : 24
                        cols         : 80
                    elt = @element.salvus_console
                        title   : "Terminal"
                        cols    : @opts.cols
                        rows    : @opts.rows
                        resizable: false
                    @console = elt.data("console")
                    @element = @console.element
                    @connect_to_server()

    connect_to_server: (cb) =>
        mesg =
            timeout    : 30  # just for making the connection; not the timeout of the session itself!
            type       : 'console'
            project_id : @editor.project_id
            cb : (err, session) =>
                if err
                    alert_message(type:'error', message:err)
                    cb?(err)
                else
                    @console.set_session(session)
                    salvus_client.write_text_file_to_project
                        project_id : @editor.project_id
                        path       : @filename
                        content    : session.session_uuid
                        cb         : cb

        if @opts.session_uuid?
            #console.log("Connecting to an existing session.")
            mesg.session_uuid = @opts.session_uuid
            salvus_client.connect_to_session(mesg)
        else
            #console.log("Opening a new session.")
            mesg.params  = {command:'bash', rows:@opts.rows, cols:@opts.cols}
            salvus_client.new_session(mesg)

        # TODO
        #@filename_tab.set_icon('console')

    _get: () =>  # TODO
        return 'history saving not yet implemented'

    _set: (content) =>  # TODO

    focus: () =>
        @console?.focus()

    terminate_session: () =>
        #@console?.terminate_session()
        @local_storage("auto_open", false)

    show: () =>
        @element.show()
        if @console?
            e = $(@console.terminal.element)
            top = @editor.editor_top_position() + @element.find(".salvus-console-topbar").height()
            e.height($(window).height() - top)
            @console.focus()

class Worksheet extends FileEditor
    constructor: (@editor, @filename, content, opts) ->
        opts = @opts = defaults opts,
            session_uuid : undefined
        @element = $("<div>Opening worksheet...</div>")  # TODO -- make much nicer
        if content?
            @_set(content)
        else
            salvus_client.read_text_file_from_project
                project_id : @editor.project_id
                timeout    : 30
                path       : filename
                cb         : (err, mesg) =>
                    if err
                        alert_message(type:"error", message:"Communications issue loading worksheet #{@filename} -- #{err}")
                    else if mesg.event == 'error'
                        alert_message(type:"error", message:"Error loading worksheet #{@filename} -- #{to_json(mesg.error)}")
                    else
                        @_set(mesg.content)

    connect_to_server: (session_uuid, cb) =>
        if @session?
            cb('already connected or attempting to connect')
            return
        @session = "init"
        async.series([
            (cb) =>
                # If the worksheet specifies a specific session_uuid,
                # try to connect to that one, in case it is still
                # running.
                if session_uuid?
                    salvus_client.connect_to_session
                        type         : 'sage'
                        timeout      : 60
                        project_id   : @editor.project_id
                        session_uuid : session_uuid
                        cb           : (err, _session) =>
                            if err
                                # NOPE -- try to make a new session (below)
                                cb()
                            else
                                # Bingo -- got it!
                                @session = _session
                                cb()
                else
                    # No session_uuid requested.
                    cb()
            (cb) =>
                if @session? and @session != "init"
                    # We successfully got a session above.
                    cb()
                else
                    # Create a completely new session on the given project.
                    salvus_client.new_session
                        timeout    : 60
                        type       : "sage"
                        project_id : @editor.project_id
                        cb : (err, _session) =>
                            if err
                                @element.text(err)  # TODO -- nicer
                                alert_message(type:'error', message:err)
                                @session = undefined
                            else
                                @session = _session
                            cb(err)
        ], cb)

    _get: () =>
        if @worksheet?
            obj = @worksheet.to_obj()
            # Make JSON nice, so more human readable *and* more diff friendly (for git).
            return JSON.stringify(obj, null, '\t')
        else
            return undefined

    _set: (content) =>
        content = $.trim(content)
        if content.length > 0
            {title, description, content, session_uuid} = from_json(content)
        else
            title = "Title"
            description = "Description"
            content = undefined
            session_uuid = undefined

        @connect_to_server session_uuid, (err) =>
            if err
                return
            @element.salvus_worksheet
                title       : title
                description : description
                content     : content
                path        : @filename
                session     : @session
                project_id  : @editor.project_id
                cwd         : misc.path_split(@editor.project_path + '/' + @filename).head

            @worksheet = @element.data("worksheet")
            @worksheet.save(@filename)
            @element   = @worksheet.element
            @worksheet.on 'save', (new_filename) =>
                if new_filename != @filename
                    @editor.change_tab_filename(@filename, new_filename)
                    @filename = new_filename

            @worksheet.on 'change', () =>
                @has_unsaved_changes(true)

    focus: () =>
        if not IS_MOBILE
            @worksheet?.focus()

    show: () =>
        if not @worksheet?
            return
        @element.show()
        win = $(window)
        @element.width(win.width())
        top = @editor.editor_top_position()
        @element.height(win.height() - top)
        bar_height = @element.find(".salvus-worksheet-controls").height()
        @element.find(".salvus-worksheet-worksheet").height(win.height() - top - bar_height)

class Image extends FileEditor
    constructor: (@editor, @filename, url, opts) ->
        opts = @opts = defaults opts,{}
        @element = $("<img>")
        if url?
            @element.attr('src', url)
        else
            salvus_client.read_file_from_project
                project_id : @editor.project_id
                timeout    : 30
                path       : @filename
                cb         : (err, mesg) =>
                    if err
                        alert_message(type:"error", message:"Communications issue loading #{@filename} -- #{err}")
                    else if mesg.event == 'error'
                        alert_message(type:"error", message:"Error getting #{@filename} -- #{to_json(mesg.error)}")
                    else
                        @element.attr('src', mesg.url)

class Spreadsheet extends FileEditor
    constructor: (@editor, @filename, content, opts) ->
        opts = @opts = defaults opts,{}
        @element = $("<div>Salvus spreadsheet not implemented yet.</div>")

class Slideshow extends FileEditor
    constructor: (@editor, @filename, content, opts) ->
        opts = @opts = defaults opts,{}
        @element = $("<div>Salvus slideshow not implemented yet.</div>")
