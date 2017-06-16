###############################################################################
#
#    CoCalc: Collaborative Calculation in the Cloud
#
#    Copyright (C) 2014--2016, SageMath, Inc.
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################

#############################################
# Editor for LaTeX documents
#############################################

$ = window.$

async           = require('async')
underscore      = require('underscore')

misc            = require('smc-util/misc')
misc_page       = require('./misc_page')
{defaults, required} = misc

{alert_message} = require('./alerts')
{redux}         = require('./smc-react')
editor          = require('./editor')
printing        = require('./printing')
{project_tasks} = require('./project_tasks')
{webapp_client} = require('./webapp_client')

templates       = $("#webapp-editor-templates")

# this regex matches the `@_get()` content iff it is a compileable latex document
RE_FULL_LATEX_CODE = new RegExp('\\\\documentclass[^}]*}[^]*?\\\\begin{document}[^]*?\\\\end{document}', 'g')

# local storage keys -- prevents typos (and keys can be shorter)
LSkey =
    ignore_invalid_latex : 'iil'
    split_pos            : 'split_pos'
    config               : 'conf'
    render_preview       : 'rp'

MAX_LATEX_ERRORS   = 10
MAX_LATEX_WARNINGS = 50
TOOLTIP_CONFIG =
    delay: {show: 500, hide: 100}

{SITE_NAME} = require('smc-util/theme')
SiteName = redux.getStore('customize').site_name ? SITE_NAME
help_md = """
# LaTeX Editor Help

LaTeX is a sophisticated markup language and processor for typesetting documents.
For a general introduction, read this [LaTeX wiki book](https://en.wikibooks.org/wiki/LaTeX) or any other resource.
In general, it works by editing source code, visible on the left, and compiling it to a PDF document,
visible on the right.
#{SiteName} manages this task for you, by regularly saving and running the LaTeX processor for you.

On the right-hand side there are several tabs like this one here for help:

* **Preview** quickly renders a few pages to see how the current part of the document looks.
* **Issues** lists all compilation warnings and errors.
  Click on the buttons to jump to the corresponding line in the input code on the left.
  _LaTeX won't compile (or only partially or in a wrong way) as long as there are any errors left!_
* **PDF** shows you an embedded view of the compiled PDF file.
  This might be broken if your browser has problems rendering the file inline –
  use the "Preview" tab instead!
* **Build** gives you advanced control over how the compilation process works:
  * **Rebuild**: erases all temporary documents and starts the compilation from scratch
  * **Latex**: triggers a "normal" Latex build, which is much faster since temporary files are retained
  * **Bibtex**: explicitly runs [Bibtex](https://en.wikipedia.org/wiki/BibTeX), usually managed by the build process
  * **Sage**: runs "SageMath" for [SageTeX](https://www.ctan.org/pkg/sagetex?lang=en), usually managed by the build process
  * **Clean**: deletes temporary files
  * **Build Command**: The drop-down list on the right hand side lets you specify the compilation program. On the left, you can edit the command even further. It is saved as part of the document, at the bottom.
By default, it runs [LatexMK](https://www.ctan.org/pkg/latexmk/) which manages temporary files and bibtex, and runs SageTeX if necessary.

## LaTeX Engines

* **latexmk** + **PDFlatex**: the default configuration, works in most cases
* **latexmk** + **XeLaTeX**: this is useful for foreign languages with many special characters.

## Features

### Forward & Inverse Search

Forward and inverse search are extremely helpful for navigating in a larger document.

**Forward**: place your cursor at a specific location in the editor on the left-hand side.
Click the "Forward" button or the `[ALT]`+`[Return]` keyboard shortcut to jump to the corresponding
location in the preview on the right-hand side.
(It might not always work in case the full positional information is not available.)

**Inverse**: Double-click on an area of interest on the right hand side in the **Preview** area.
The cursor on the left-hand side will jump to the paragraph in the source-code.

## Quickstart

It is very easy to start with LaTeX.
#{SiteName} guides your first document with a small default template.
You start working between the `\\begin{document}` and `\\end{document}` instructions.
Everything before `\\begin{document}` is called the "preamble" and contains the configuration for the document.

For example, remove the `\\maketitle` instruction and replace it by

> `Hello \\textbf{#{SiteName}}! This is a formula: $\\frac{1}{1+x^2}$.`

After saving (`[CTRL]` + `[s]`), there should be a small spinner next to `Build` and once done,
the preview renders. You should then see:

> Hello **#{SiteName}**! This is a formula: $\\frac{1}{1+x^2}$.

* **New paragraphs**: Single returns for new lines do not have any effect.
  Use them to keep new sentences in paragraphs at the beginning of a line for better overview.
  Two or more returns introduce a new paragraph.
* **Formulas**: They're either between `$` or `$$`, or in `\\begin{equation}...\\end{equation}` environments.

## Encoding

**UTF8**: the build process runs in a Linux environment.
All edited documents are assumed to be encoded as UTF-8.
Therefore, depending if you compile via PDFLaTeX or XeLaTeX, the following encoding defintions are the preferred choices:

* PDFLaTeX:
  ```
  \\usepackage[T1]{fontenc}
  \\usepackage[utf8]{inputenc}
  \\usepackage{lmodern}
  ```
* XeLaTeX:
  ```
  \\usepackage{fontspec}
  ```

The default template already selects the correct configuration for you.

## FAQ

### How to insert an image?

1. Upload a PNG or PDF file via #{SiteName}'s "Files" interface.
   The uploaded image should be in the same directory as the `.tex` file
   Otherwise, use relative paths like `./images/filename.png` if it is in a subdirectory `images`.
2. Follow [these instructions](https://en.wikibooks.org/wiki/LaTeX/Floats,_Figures_and_Captions)
   about how to insert a graphic in a figure environment.
   Do not forget `\\usepackage{graphicx}` in the preamble declaration.

### How to insert a backslash or dollar sign?

The `\\` character has a special meaning.
It signals a LaTeX command or is used as an escape character.
To enter a backslash, escape its meaning by entering it twice: `\\\\`.

A dollar sign is entered as `\\$`, which escapes the meaning of "formula-start".

### What to do if the preview does not update

Possible reasons:

1. Are there any errors in the "Issues" tab? LaTeX only compiles well if there are zero reported errors.
2. Long documents could take an extended period of time to complete. In the "Preview" tab, disable the preview and only enable it once to avoid piling up too much work on the back-end.
3. Similarly, computational-heavy "SageTeX" computations could lead to excessive compilation times.
   You can pre-compute results or split the document into smaller parts.

### How to deal with large documents across multiple source files?

The best way is to use the [subfiles](https://www.ctan.org/pkg/subfiles?lang=en) package as [described here](https://en.wikibooks.org/wiki/LaTeX/Modular_Documents#Subfiles).
Here is an extended example demonstrating how this works: [cloud-examples/latex/multiple-files](https://github.com/sagemath/cloud-examples/tree/master/latex/multiple-files).
"""

class exports.LatexEditor extends editor.FileEditor
    constructor: (@project_id, @filename, content, opts) ->
        super(@project_id, @filename)

        # The are three components:
        #     * latex_editor -- a CodeMirror editor
        #     * preview -- display the images (page forward/backward/resolution)
        #     * log -- log of latex command
        opts.mode = 'stex2'

        @element = templates.find(".webapp-editor-latex").clone()

        @_pages = {}

        # this maps tex line numbers to the ones in the Rnw file via an array
        @_rnw_concordance = null

        # initialize the latex_editor
        opts.latex_editor = true
        @latex_editor = editor.codemirror_session_editor(@project_id, @filename, opts)
        @_pages['latex_editor'] = @latex_editor
        @element.find(".webapp-editor-latex-latex_editor").append(@latex_editor.element)
        @element.find(".webapp-editor-codeedit-buttonbar-mode").remove()

        @latex_editor.action_key = @action_key
        @element.find(".webapp-editor-latex-buttons").show()

        latex_buttonbar = @element.find(".webapp-editor-latex-buttonbar")
        latex_buttonbar.show()

        @latex_editor.on 'saved', () =>
            @update_preview () =>
                if @_current_page == 'pdf-preview'
                    @preview_embed?.update()
            @spell_check()

        @latex_editor.syncdoc.on 'connect', () =>
            @preview.zoom_width = @load_conf().zoom_width ? 100
            @update_preview()
            @spell_check()

        @latex_editor.print = () =>
            outfn = misc.change_filename_extension(@filename, 'pdf')
            printing.Printer(@, outfn).print()
            return false

        v = misc.path_split(@filename)
        @_path = v.head
        @_target = v.tail

        # initialize the previews
        n = @filename.length

        # The pdf preview.
        @preview = new editor.PDF_Preview(@project_id, @filename, undefined, {resolution:@get_resolution()})
        @element.find(".webapp-editor-latex-png-preview").append(@preview.element)
        @_pages['png-preview'] = @preview
        @preview.on 'shift-click', (opts) => @_inverse_search(opts)

        # Embedded pdf page (not really a "preview" -- it's the real thing).
        # see https://github.com/sagemathinc/cocalc/issues/1313
        # it was broken on Firefox, but as of version 53 it works
        preview_filename = misc.change_filename_extension(@filename, 'pdf')
        @preview_embed = new editor.PDF_PreviewEmbed(@project_id, preview_filename, undefined, {})
        @preview_embed.element.find(".webapp-editor-codemirror-button-row").remove()
        @element.find(".webapp-editor-latex-pdf-preview").append(@preview_embed.element)
        @_pages['pdf-preview'] = @preview_embed

        # Initalize the log
        @log = @element.find(".webapp-editor-latex-log")
        @log.find("a").tooltip(TOOLTIP_CONFIG)
        @_pages['log'] = @log
        @log_input = @log.find("input")
        @log_input.tooltip(TOOLTIP_CONFIG)
        save_custom_build_command = () =>
            @set_conf_doc(latex_command: @log_input.val())
            @save()
        @log_input.keyup (e) =>
            if e.keyCode == 13
                save_custom_build_command()
        @log_input.on('blur', save_custom_build_command)

        # Custom build command menu
        dropdown = @element.find(".smc-editor-latex-log-cmd .dropdown-menu")
        dropdown.on 'click', 'li', (ev) =>
            ev.preventDefault()
            flavor = ev.target.hash ? '#default'
            c = @preview.pdflatex.default_tex_command(flavor[1..])
            # console.log(c)
            @log_input.val(c)
            @set_conf_doc(latex_command: c)
            @save()
            return true

        for cm in @cms()
            cm._smc_inline_errors = {}
        @element.on 'blur', ->
            $('[data-toggle="popover"]').popover('hide')
        @errors = @element.find(".webapp-editor-latex-errors")
        @_pages['errors'] = @errors
        @_error_message_template = @element.find(".webapp-editor-latex-mesg-template")

        @help = @element.find('.webapp-editor-latex-help')
        markdown = require('./markdown')
        @help.html(markdown.markdown_to_html(help_md).s)
        @_pages['help'] = @help

        @_init_buttons()
        @init_draggable_split()

        # if the latex file should be compiled and the preview rendered
        # must come after _init_buttons
        @_render_preview = @local_storage(LSkey.render_preview) ? true
        @set_toggle_preview_state(@_render_preview)

        # This synchronizes the editor and png preview -- it's kind of disturbing.
        # If people request it, make it a non-default option...
        ###
            @preview.page.on 'scroll', @_passive_inverse_search
            cm0 = @latex_editor.codemirror
            cm1 = @latex_editor.codemirror1
            cm0.on 'cursorActivity', @_passive_forward_search
            cm1.on 'cursorActivity', @_passive_forward_search
            cm0.on 'change', @_pause_passive_search
            cm1.on 'change', @_pause_passive_search
        ###

    cms: =>
        return @latex_editor.codemirrors()

    spell_check: (cb) =>
        @preview.pdflatex.spell_check
            lang : @load_conf_doc().lang
            cb   : (err, words) =>
                if err
                    cb?(err)
                else
                    for cm in @cms()
                        cm.spellcheck_highlight(words)

    init_draggable_split: () =>
        @_split_pos = @local_storage(LSkey.split_pos)
        @_dragbar = dragbar = @element.find(".webapp-editor-latex-resize-bar")
        @set_dragbar_position()
        update = =>
            misc_page.drag_stop_iframe_enable()
            # compute the position of bar as a number from 0 to 1
            left  = @element.offset().left
            width = @element.width()
            p     = dragbar.offset().left
            @_split_pos = (p - left) / width
            @local_storage(LSkey.split_pos, @_split_pos)
            dragbar.css(left: 0)
            @set_dragbar_position()


        dragbar.draggable
            axis        : 'x'
            containment : @element
            zIndex      : 10
            stop        : update
            start       : misc_page.drag_start_iframe_disable

    set_dragbar_position: =>
        @_split_pos ?= @local_storage(LSkey.split_pos) ? 0.5
        @_split_pos = Math.max(editor.MIN_SPLIT, Math.min(editor.MAX_SPLIT, @_split_pos))
        @element.find(".webapp-editor-latex-latex_editor").css('flex-basis',"#{@_split_pos*100}%")

    set_conf: (obj) =>
        conf = @load_conf()
        for k, v of obj
            conf[k] = v
        @save_conf(conf)

    load_conf: () =>
        conf = @local_storage(LSkey.config)
        if not conf?
            conf = {}
        return conf

    save_conf: (conf) =>
        @local_storage(LSkey.config, conf)

    set_conf_doc: (obj) =>
        conf = @load_conf_doc()
        for k, v of obj
            conf[k] = v
        @save_conf_doc(conf)

    load_conf_doc: () =>
        if not @latex_editor.codemirror?
            return {}
        doc = @latex_editor.codemirror.getValue()
        i_old = doc.indexOf('%sagemathcloud=')
        i_new = doc.indexOf('%configuration=')
        i = Math.max(i_old, i_new)
        if i == -1
            return {}

        j = doc.indexOf('=',i)
        k = doc.indexOf('\n',i)
        if k == -1
            k = doc.length
        try
            conf = misc.from_json(doc.slice(j+1,k))
        catch e
            conf = {}

        return conf

    save_conf_doc: (conf) =>
        cm  = @latex_editor.codemirror
        if not cm?
            return
        doc = cm.getValue()
        i_old = doc.indexOf('%sagemathcloud=')
        i_new = doc.indexOf('%configuration=')
        i = Math.max(i_old, i_new)
        line = '%configuration=' + misc.to_json(conf)
        if i != -1
            # find the line m where it is already
            for n in [cm.doc.lastLine()..0]
                z = cm.getLine(n)
                i2_old = z.indexOf('%sagemathcloud=')
                i2_new = z.indexOf('%configuration=')
                i2 = Math.max(i2_old, i2_new)
                if i2 != -1
                    m = n
                    break
            cm.replaceRange(line+'\n', {line:m,ch:0}, {line:m+1,ch:0})
        else
            if misc.len(conf) == 0
                # don't put it in there if empty
                return
            cm.replaceRange('\n'+line, {line:cm.doc.lastLine()+1,ch:0})
        @latex_editor.syncdoc.sync()

    _pause_passive_search: (cb) =>
        @_passive_forward_search_disabled = true
        @_passive_inverse_search_disabled = true
        f = () =>
            @_passive_inverse_search_disabled = false
            @_passive_forward_search_disabled = false

        setTimeout(f, 3000)

    _passive_inverse_search: (cb) =>
        if @_passive_inverse_search_disabled
            cb?(); return
        @_pause_passive_search()
        @inverse_search
            active : false
            cb     : (err) =>
                cb?()

    _passive_forward_search: (cb) =>
        if @_passive_forward_search_disabled
            cb?(); return
        @forward_search
            active : false
            cb     : (err) =>
                @_pause_passive_search()
                cb?()

    action_key: () =>
        @show_page('png-preview')
        @forward_search(active:true)

    remove: () =>
        @latex_editor.remove()
        @element.remove()
        @preview.remove()
        @preview_embed?.remove()

    _init_buttons: () =>
        @element.find("a").tooltip(TOOLTIP_CONFIG)

        @element.find('a[href="#forward-search"]').click () =>
            @show_page('png-preview')
            @forward_search(active:true)
            return false

        @element.find('a[href="#inverse-search"]').click () =>
            @show_page('png-preview')
            @inverse_search(active:true)
            return false

        @element.find('a[href="#png-preview"]').click () =>
            @show_page('png-preview')
            @preview.focus()
            @save()
            return false

        @element.find('a[href="#help"]').click () =>
            @show_page('help')
            return false

        @element.find('a[href="#zoom-preview-out"]').click () =>
            @preview.zoom(delta: -5)
            @set_conf(zoom_width: @preview.zoom_width)
            return false

        @element.find('a[href="#zoom-preview-in"]').click () =>
            @preview.zoom(delta:5)
            @set_conf(zoom_width:@preview.zoom_width)
            return false

        @element.find('a[href="#zoom-preview-fullpage"]').click () =>
            @preview.zoom(width:100)
            @set_conf(zoom_width:@preview.zoom_width)
            return false

        @element.find('a[href="#zoom-preview-width"]').click () =>
            @preview.zoom(width:160)
            @set_conf(zoom_width:@preview.zoom_width)
            return false

        @element.find('a[href="#pdf-preview"]').click () =>
            # see https://github.com/sagemathinc/cocalc/issues/1313
            # it was broken on Firefox, but as of version 53 it works
            @show_page('pdf-preview')
            @preview_embed.focus()
            @preview_embed.update()
            return false

        @element.find('a[href="#log"]').click () =>
            @show_page('log')
            t = @log.find("textarea")
            t.scrollTop(t[0].scrollHeight)
            return false

        @element.find('a[href="#errors"]').click () =>
            @show_page('errors')
            return false

        @number_of_errors = @element.find('a[href="#errors"]').find(".webapp-latex-errors-counter")
        @number_of_warnings = @element.find('a[href="#errors"]').find(".webapp-latex-warnings-counter")

        @element.find('a[href="#pdf-download"]').click () =>
            @download_pdf()
            return false

        @element.find('a[href="#preview-resolution"]').click () =>
            @set_resolution()
            return false

        @_toggle_preview_button = @element.find('a[href="#toggle-preview"]')
        @_toggle_preview_button.click () =>
            @toggle_preview()
            return false

        #@element.find("a[href=\"#latex-command-undo\"]").click () =>
        #    c = @preview.pdflatex.default_tex_command()
        #    @log_input.val(c)
        #    @set_conf_doc(latex_command: c)
        #    return false

        trash_aux_button = @element.find('a[href="#latex-trash-aux"]')
        trash_aux_button.click () =>
            trash_aux_button.icon_spin(true, disable=true)
            log_output = @log.find("textarea")
            log_output.text('')
            # now we actually delete the files and report any errors in the log
            @preview.pdflatex.trash_aux_files (err, log) =>
                if err
                    log_output.text(err)
                else
                    log_output.text(log)
                # after deleting the log also clear all issues!
                @preview.pdflatex.last_latex_log = ''
                @render_error_page()
                trash_aux_button.icon_spin(false, disable=true)
            return false

        run_sage = @element.find('a[href="#latex-sage"]')
        run_sage.click () =>
            @log.find("textarea").text("Running Sage...")
            run_sage.icon_spin(true, disable=true)
            @preview.pdflatex._run_sage undefined, (err, log) =>
                run_sage.icon_spin(false, disable=true)
                @log.find("textarea").text(log)
            return false

        run_latex = @element.find('a[href="#latex-latex"]')
        run_latex.click () =>
            @log.find("textarea").text("Running Latex...")
            run_latex.icon_spin(true, disable=true)
            @preview.pdflatex._run_latex @load_conf_doc().latex_command, (err, log) =>
                @log.find("textarea").text(log)
                # the log changed, there could be issues, render them
                @render_error_page()
                run_latex.icon_spin(false, disable=true)
            return false

        run_recompile = @element.find('a[href="#latex-recompile"]')
        run_recompile.click () =>
            log_box = @log.find("textarea")
            log_box.text("Recompiling ...")
            run_recompile.icon_spin(true, disable=true)
            async.series([
                (cb) =>
                    @preview.pdflatex.trash_aux_files (err, _log) =>
                        cb(err)
                (cb) =>
                    @update_preview(cb, force=true, only_compile=true)
            ], (err) =>
                run_recompile.icon_spin(false, disable=true)
            )
            return false

        run_bibtex = @element.find('a[href="#latex-bibtex"]')
        run_bibtex.click () =>
            @log.find("textarea").text("Running Bibtex...")
            run_bibtex.icon_spin(true, disable=true)
            @preview.pdflatex._run_bibtex (err, log) =>
                run_bibtex.icon_spin(false, disable=true)
                @log.find("textarea").text(log)
            return false

    set_resolution: (res) =>
        if not res?
            bootbox.prompt "Change preview resolution from #{@get_resolution()} dpi to...", (result) =>
                if result
                    @set_resolution(result)
        else
            try
                res = parseInt(res)
                if res < 75
                    res = 75
                else if res > 600
                    res = 600
                @preview.opts.resolution = res
                @set_conf(resolution : res)
                @preview.update()
            catch e
                alert_message
                    type    : "error"
                    message : "Invalid resolution #{res}"

    get_resolution: () =>
        if not @preview?
            return @load_conf()['resolution'] ? 150
        return @preview.opts.resolution

    # This function isn't called on save button click since
    # the codemirror's save button is called...
    click_save_button: () =>
        @latex_editor.click_save_button()

    # This function isn't called on save
    # @latex_editor.save is called instead for some reason
    save: (cb, force=false) =>
        @latex_editor.save (err) =>
            cb?(err)
            if not err
                @update_preview (force=force) =>
                    if @_current_page == 'pdf-preview'
                        @preview_embed?.update()
                @spell_check()

    update_preview: (cb, force=false, only_compile=false) =>
        # force: continue, even when content hasn't changed
        # only_compile: avoid the preview rendering
        # obvious TODO: untangle preview update and run_latex
        if not only_compile and not @_render_preview
            cb?()
            return

        # no content available, hence nothing to preview
        if not @latex_editor.syncdoc._fully_loaded
            cb?()
            return

        content = @_get()
        # issue #1814
        if not content?
            cb?()
            return

        if not force and content == @_last_update_preview
            cb?()
            return

        latex_command = @load_conf_doc().latex_command
        filename_tex  = @preview.pdflatex.filename_tex
        # a check, if we're really compiling the edited latex file
        if latex_command?  # could be undefined
            compiling_this_file = latex_command.indexOf(filename_tex) >= 0
        else
            compiling_this_file = true

        # check if latex file is invalid iff we're compiling it
        iil = @local_storage(LSkey.ignore_invalid_latex) ? false
        if not iil and not content.match(RE_FULL_LATEX_CODE) and compiling_this_file and not only_compile
            msg = @invalid_latex(filename_tex)
            @preview.show_message(msg)
            cb?()
            return

        if @_render_preview and not only_compile
            @preview.show_pages(true)
        preview_button = @element.find('a[href="#png-preview"]')
        async.series([
            (cb) =>
                @_last_update_preview = content
                if @latex_editor.has_unsaved_changes()
                    @latex_editor.save(cb)
                else
                    cb()
            (cb) =>
                if @latex_editor.has_uncommitted_changes()
                    delete @_last_update_preview  # running latex on stale version
                    @get_rnw_concordance_error = false
                @run_latex
                    command      : @load_conf_doc().latex_command
                    cb           : cb
            (cb) =>
                if only_compile
                    cb(); return
                preview_button.icon_spin(true, disable=true)
                @preview.update
                    cb: cb
        ], (err) =>
            if not only_compile
                preview_button.icon_spin(false, disable=true)
            if err
                delete @_last_update_preview
            cb?(err)
        )

    _get: () =>
        return @latex_editor._get()

    _set: (content) =>
        @latex_editor._set(content)

    _show: (opts={}) =>
         # Workaround Safari flex layout bug https://github.com/philipwalton/flexbugs/issues/132
        if $.browser.safari
            @element.make_height_defined()

        if not @_show_before?
            @show_page('png-preview')
            @_show_before = true
        else
            @show_page()

    focus: () =>
        @latex_editor?.focus()

    has_unsaved_changes: (val) =>
        return @latex_editor?.has_unsaved_changes(val)

    show_page: (name) =>
        if not name?
            name = @_current_page
        @_current_page = name
        if not name?
            name = 'png-preview'

        pages = ['png-preview', 'pdf-preview', 'log', 'errors', 'help']
        for n in pages
            @element.find(".webapp-editor-latex-#{n}").hide()

        for n in pages
            page = @_pages[n]
            if not page?
                continue
            e = @element.find(".webapp-editor-latex-#{n}")
            button = @element.find("a[href=\"#" + n + "\"]")
            if n == name
                e.show()
                if n == 'log'
                    c = @load_conf_doc().latex_command
                    if c
                        @log_input.val(c)
                else if n == 'errors'
                    @render_error_page()
                else if n == 'help'
                    e.mathjax()
                    e.find('a').attr('target', '_blank')
                else
                    page.show()
                button.parent().addClass('active')
            else
                button.parent().removeClass('active')

    run_latex: (opts={}) =>
        opts = defaults opts,
            command      : undefined
            cb           : undefined
        button = @element.find('a[href="#log"]')
        button.icon_spin(true, disable=true)
        @_show() # update layout, since showing spinner might cause a linebreak in the button bar
        log_output = @log.find("textarea")
        log_output.text("")
        if not opts.command?
            opts.command = @preview.pdflatex.default_tex_command()
        @log_input.val(opts.command)

        build_status = button.find(".webapp-latex-build-status")
        status = (mesg) =>
            if mesg.start
                build_status.text(' - ' + mesg.start)
                log_output.text(log_output.text() + '\n\n-----------------------------------------------------\nRunning ' + mesg.start + '...\n\n\n\n')
            else
                if mesg.end == 'latex'
                    @render_error_page()
                build_status.text('')
                log_output.text(log_output.text() + '\n' + mesg.log + '\n')
            # Scroll to the bottom of the textarea
            log_output.scrollTop(log_output[0].scrollHeight)

        @preview.pdflatex.update_pdf
            status        : status
            latex_command : opts.command
            cb            : (err, log) =>
                button.icon_spin(false, disable=true)
                @_show() # update layout, since hiding spinner might cause a linebreak in the button bar to go away
                opts.cb?()

    render_error_page: () =>
        # looks bad, but it isn't: @_render_error_page is synchronized at it's heart
        async.series([
            @get_rnw_concordance,
            @_render_error_page
        ])

    _render_error_page: (cb) =>
        log = @preview.pdflatex.last_latex_log
        if not log?
            cb()
            return
        {LatexParser} = require('latex/latex-log-parser.coffee')
        p = (new LatexParser(log, {ignoreDuplicates: true})).parse()

        if p.errors.length
            @number_of_errors.text("  (#{p.errors.length})")
            @element.find('a[href="#errors"]').addClass("btn-danger")
        else
            @number_of_errors.text('')
            @element.find('a[href="#errors"]').removeClass("btn-danger")

        k = p.warnings.length + p.typesetting.length
        if k and p.errors.length == 0  # don't show if there are errors
            @number_of_warnings.text("  (#{k})")
        else
            @number_of_warnings.text('')

        @_reset_inline_errors()

        if @_current_page != 'errors'
            # just render the error messages for the inline information
            for [t, msgs] in [['error', p.errors],
                              ['warning', p.warnings],
                              ['typesetting', p.typesetting]]
                for msg in msgs
                    @render_error_message(msg, t, inline_only = true)
            cb()
            return

        elt = @errors.find(".webapp-latex-errors")
        if p.errors.length == 0
            elt.html("None")
        else
            elt.html("")
            cnt = 0
            for mesg in p.errors
                cnt += 1
                if cnt > MAX_LATEX_ERRORS
                    elt.append($("<h4>(Not showing #{p.errors.length - cnt + 1} additional errors.)</h4>"))
                    break
                elt.append(@render_error_message(mesg, 'error'))

        elt = @errors.find(".webapp-latex-warnings")
        if p.warnings.length == 0
            elt.html("None")
        else
            elt.html("")
            cnt = 0
            for mesg in p.warnings
                cnt += 1
                if cnt > MAX_LATEX_WARNINGS
                    elt.append($("<h4>(Not showing #{p.warnings.length - cnt + 1} additional warnings.)</h4>"))
                    break
                elt.append(@render_error_message(mesg, 'warning'))

        elt = @errors.find(".webapp-latex-typesetting")
        if p.typesetting.length == 0
            elt.html("None")
        else
            elt.html("")
            cnt = 0
            for mesg in p.typesetting
                cnt += 1
                if cnt > MAX_LATEX_WARNINGS
                    elt.append($("<h4>(Not showing #{p.typesetting.length - cnt + 1} additional typesetting issues.)</h4>"))
                    break
                elt.append(@render_error_message(mesg, 'typesetting'))
        cb()

    _reset_inline_errors: () =>
        $('[data-toggle="popover"]').popover('hide')
        for cm in @cms()
            cm.clearGutter('Codemirror-latex-errors')
            for line, line_handler of cm._smc_inline_errors
                # use line_handler to always find the correct line
                cm.removeLineClass(line_handler, 'background')
            cm._smc_inline_errors = {}

    _render_inline_error: (line, message, content, error_type) =>
        line -= 1 # to get 0-based numbering for the remaining code
        if error_type != 'error' or not @latex_editor.codemirror?
            # only show errors, warnings and typesettings are too verbose
            return
        # at most one error widget per line ...
        if line of @latex_editor.codemirror._smc_inline_errors
            return

        if content?
            con = document.createElement('code')
            con.className = 'smc-latex-inline-error-content'
            con_lines = content.split(/\r?\n/)
            if con_lines.length >= 5
                con_lines = con_lines[...4]
                con_lines.push('[...]')
            content = con_lines.join('\n')
            con.appendChild(document.createTextNode(content))
            content = con.outerHTML

        icon = $("""
            <i style="color: #d9534f; cursor: pointer;"
            class="fa fa-exclamation-triangle"
            aria-hidden="true"
            data-container="body"
            data-toggle="popover"
            data-placement="right"
            title="#{message}">
            </i>""")

        # from http://getbootstrap.com/javascript/#popovers-options
        popup_template = """<div class="popover smc-latex-error-popover" role="tooltip">
        <div class="arrow"></div>
        <h3 class="popover-title"></h3>
        <pre class="popover-content"></pre>
        </div>
        """

        icon.popover(
            trigger  : 'hover'
            html     : true
            content  : content ? ''
            delay    : { "show": 10, "hide": 100 }
            template : popup_template
        )

        conf = {coverGutter: false, noHScroll: true}
        for cm in @cms()
            cm.setGutterMarker(line, 'Codemirror-latex-errors', icon.get(0))
            line_handler = cm.addLineClass(line, 'background', "smc-latex-inline-error-#{error_type}")
            cm._smc_inline_errors[line] = line_handler

    _show_error_in_file: (mesg, cb) =>
        file = mesg.file
        if not file
            alert_message
                type    : "error"
                message : "Unable to open unknown file."
            cb?()
            return
        if not mesg.line
            if mesg.page
                @_inverse_search
                    n          : mesg.page
                    active     : false
                    x          : 50
                    y          : 50
                    resolution : @get_resolution()
                    cb         : cb
            else
                alert_message
                    type    : "error"
                    message : "Unknown location in '#{file}'."
                cb?()
                return
        else
            if file in [@preview.pdflatex.filename_tex, @preview.pdflatex.filename_rnw]
                @latex_editor.set_cursor_center_focus({line:mesg.line-1, ch:0})
            else
                if @_path # make relative to home directory of project
                    file = @_path + '/' + file
                redux.getProjectActions(@project_id).open_file
                    path : file
            cb?()

    _show_error_in_preview: (mesg) =>
        @_show_error_in_file mesg, () =>
            @show_page('png-preview')
            @forward_search(active:true)

    render_error_message: (mesg, error_type, inline_only = false) =>
        if mesg.file?.slice(0,2) == './'
            mesg.file = mesg.file.slice(2)

        if mesg.line and @preview.pdflatex.ext == 'rnw'
            mesg.line = @rnw_concordance(mesg.line)
            mesg.file = @preview.pdflatex.filename_rnw

        # render inline error information
        if mesg.line and mesg.file in [@preview.pdflatex.filename_tex, @preview.pdflatex.filename_rnw]
            @_render_inline_error(mesg.line, mesg.message, mesg.content, error_type)

        if inline_only
            return

        if not mesg.line
            r = mesg.raw
            i = r.lastIndexOf('[')
            j = i+1
            while j < r.length and r[j] >= '0' and r[j] <= '9'
                j += 1
            mesg.page = r.slice(i+1,j)

        elt = @_error_message_template.clone().show()
        elt.find("a:first").click () =>
            @_show_error_in_file(mesg)
            return false
        elt.find("a:last").click () =>
            @_show_error_in_preview(mesg)
            return false

        elt.addClass("webapp-editor-latex-mesg-template-#{mesg.level}")
        if mesg.line
            elt.find(".webapp-latex-mesg-line").text("line #{mesg.line}").data('line', mesg.line)
        if mesg.page
            elt.find(".webapp-latex-mesg-page").text("page #{mesg.page}").data('page', mesg.page)
        if mesg.file
            elt.find(".webapp-latex-mesg-file").text(" of #{mesg.file}").data('file', mesg.file)
        if mesg.message
            elt.find(".webapp-latex-mesg-message").text(mesg.message)
        if mesg.content
            elt.find(".webapp-latex-mesg-content").show().text(mesg.content)
        return elt

    # convert line number of tex file to line number in Rnw file
    rnw_concordance: (line) =>
        if not @_rnw_concordance?
            # TODO linear interpolation using line number of tex vs. @latex_editor.lineCount()
            return line
        ret = @_rnw_concordance[line - 1] ? line
        # console.log("associated line of #{line} is #{ret}")
        return ret

    get_rnw_concordance: (cb) =>
        if @get_rnw_concordance_error
            cb(); return
        # always call the cb without an error -- otherwise the errors don't show up at all
        if @preview.pdflatex.ext == 'rnw'
            conc_fn = @preview.pdflatex.base_filename + '-concordance.tex'
            if @_path # make relative to home directory of project
                conc_fn = @_path + '/' + conc_fn
            webapp_client.read_text_file_from_project
                project_id : @project_id
                path       : conc_fn
                cb         : (err, res) =>
                    err ?= res.error
                    if err
                        console.warn("Unable to read concordance file #{conc_fn} -- #{misc.to_json(err)}")
                        @get_rnw_concordance_error = true
                    else
                        # concordance file is explained here:
                        # https://cran.r-project.org/web/packages/patchDVI/vignettes/patchDVI.pdf
                        try
                            c = res.content
                            c = c.split('%')[1..].join(' ').replace(/\n/g, '')
                            c = c[...c.indexOf('}')]
                            enc  = (parseInt(n) for n in c.split(/[ ]+/))
                            # enc is now the list of RLE encoded numbers
                            line = enc[0] - 1 # start line, zero-based
                            orig = 0
                            dec  = []     # decoded RLE encoding
                            for idx in [1...enc.length] by 2
                                for i in [0...enc[idx]]
                                    orig += enc[idx + 1]
                                    dec.push(orig)
                            # console.log('@_rnw_concordance', @_rnw_concordance)
                            @_rnw_concordance = dec
                        catch e
                            # don't reset @_rnw_concordance, the old one could be good enough
                            console.warn("problem reading and processing #{conc_fn}:", e)
                            console.trace()
                    cb()
        else
            cb()

    download_pdf: (print = false) =>
        redux.getProjectActions(@project_id).download_file
            path : misc.change_filename_extension(@filename, 'pdf')
            print: print

    # this sets the "visual state" for @_render_preview
    set_toggle_preview_state: (enabled) =>
        @local_storage(LSkey.render_preview, enabled)
        @_toggle_preview_button.toggleClass('active', enabled)
        @_toggle_preview_button.attr('aria-pressed', enabled)
        icon = @_toggle_preview_button.find('i')
        icon.toggleClass('fa-check-square-o', enabled)
        icon.toggleClass('fa-square-o', !enabled)

        if enabled
            @preview.show_pages(true)
            @preview.update()
        else
            m = $('<div>Preview disabled. Click <a href="#">here</a> to enable.</div>')
            m.find('a').click =>
                @toggle_preview(true)
            @preview.show_message(m)

    toggle_preview: (enabled) =>
        # enabled could be undefined, but @_render_preview is always defined
        enabled = @_render_preview = (enabled ? ! @_render_preview)
        @set_toggle_preview_state(enabled)
        hide_errors = =>
            if not enabled
                @preview.pdflatex.last_latex_log = ''
                @render_error_page()
        @save(hide_errors, force=enabled)

    # Warning text, if regex RE_FULL_LATEX_CODE doesn't match content
    invalid_latex: (filename) =>
        msg = $("""
        <h2>Invalid LaTeX document</h2>
        <div>
        Sorry, it is not possible to render a preview of the document
        <code>#{filename}</code>.
        A minimal LaTeX document must consist of:

        <pre>
        \\documentclass{...}  % e.g. \\documentclass{article}
        % preamble ...
        \\begin{document}
        ...
        \\end{document}
        </pre>

        <div>
        For more information:
        <a href="https://en.wikibooks.org/wiki/LaTeX/Document_Structure"
            target="_blank">WikiBooks LaTeX</a>
        </div>

        <div style="margin-top: 25px; text-align: center;">
        <a class="btn btn-lg btn-primary" href="#ignore">
            Ignore this warning and compile
        </a>
        </div>
        </div>
        """)
        msg.find('a[href="#ignore"]').click =>
            @ignore_invalid_latex()
        return msg

    ignore_invalid_latex: =>
        @local_storage(LSkey.ignore_invalid_latex, true)
        @save(null, force=true)

    _inverse_search: (opts) =>
        active = opts.active  # whether user actively clicked, in which case we may open a new file -- otherwise don't open anything.
        delete opts.active
        cb = opts.cb
        opts.cb = (err, res) =>
            if err
                if active
                    alert_message
                        type    : "error"
                        message : "Inverse search error -- #{err}"
            else
                # lowercase needed, because synctex automatically uppercases .Rnw
                if res.input.toLocaleLowerCase() != @filename.toLocaleLowerCase()
                    if active
                        redux.getProjectActions(@project_id).open_file
                            path : res.input
                else
                    @latex_editor.set_cursor_center_focus({line:res.line, ch:0})
            cb?()

        @preview.pdflatex.inverse_search(opts)

    inverse_search: (opts={}) =>
        opts = defaults opts,
            active : required
            cb     : undefined
        number = @preview.current_page().number
        elt    = @preview.pdflatex.page(number).element
        if not elt?
            opts.cb?("Preview not yet loaded.")
            return
        page   = @preview.page
        nH     = elt.find("img")[0].naturalHeight
        y      = (page.height()/2 + page.offset().top - elt.offset().top) * nH / elt.height()
        @_inverse_search({n:number, x:0, y:y, resolution:@preview.pdflatex.page(number).resolution, cb:opts.cb})

    forward_search: (opts={}) =>
        opts = defaults opts,
            active : true
            cb     : undefined
        cm = @latex_editor.codemirror_with_last_focus
        if not cm?
            opts.cb?()
            return
        n = cm.getCursor().line + 1
        @preview.pdflatex.forward_search
            n  : n
            cb : (err, result) =>
                if err
                    if opts.active
                        alert_message(type:"error", message:err)
                else
                    y = result.y
                    pg = @preview.pdflatex.page(result.n)
                    res = pg.resolution
                    img = pg.element?.find("img")
                    if not img?
                        opts.cb?("Page #{result.n} not yet loaded.")
                        return
                    nH = img[0].naturalHeight
                    if not res?
                        y = 0
                    else
                        y *= res / 72 * img.height() / nH
                    @preview.scroll_into_view
                        n              : result.n
                        y              : y
                        highlight_line : true
                opts.cb?(err)