/*
Some async utils.

(Obviously should be moved somewhere else when the dust settles!)

The two helpful async/await libraries I found are:

   - https://github.com/hunterloftis/awaiting
   - https://github.com/masotime/async-await-utils

*/

import * as awaiting from "awaiting";

// turns a function of opts, which has a cb input into
// an async function that takes an opts with no cb as input; this is just like
// awaiting.callback, but for our functions that take opts.
export function callback_opts(f: Function) {
  return async function(opts: any) : Promise<any> {
    function g(cb: Function) {
      opts.cb = cb;
      f(opts);
    }
    return await awaiting.callback(g);
  }
}

/* retry_until_success keeps calling an async function f with
  exponential backoff until f does NOT raise an exception.
  Then retry_until_success returns whatever f returned.
*/

interface RetryUntilSuccess {
  f: () => Promise<any>; // an async function that takes no input.
  start_delay?: number; // delay (in ms) before calling second time.
  max_delay?: number; // delay at most this amount between calls
  max_tries?: number; // maximum number of times to call f
  max_time?: number; // milliseconds -- don't call f again if the call would start after this much time from first call
  factor?: number; // multiply delay by this each time
}

export async function retry_until_success(
  opts: RetryUntilSuccess
): Promise<any> {
  if (!opts.start_delay) opts.start_delay = 100;
  if (!opts.max_delay) opts.max_delay = 20000;
  if (!opts.factor) opts.factor = 1.4;

  let next_delay: number = opts.start_delay;
  let tries: number = 0;
  let start_time: number = new Date().valueOf();
  let last_exc: Error | undefined;

  // Return nonempty string if time or tries exceeded.
  function check_done(): string {
    if (
      opts.max_time &&
      next_delay + new Date().valueOf() - start_time > opts.max_time
    ) {
      return "maximum time exceeded";
    }
    if (opts.max_tries && tries >= opts.max_tries) {
      return "maximum tries exceeded";
    }
    return "";
  }

  while (true) {
    try {
      return await opts.f();
    } catch (exc) {
      // might try again -- update state...
      tries += 1;
      next_delay = Math.min(opts.max_delay, opts.factor * next_delay);
      // check if too long or too many tries
      let err = check_done();
      if (err) {
        // yep -- game over, throw an error
        if (last_exc) {
          throw Error(`${err} -- last error was ${last_exc}`);
        } else {
          throw Error(err);
        }
      }
      // record exception so can use it later.
      last_exc = exc;

      // wait before trying again
      await awaiting.delay(next_delay);
    }
  }
}
