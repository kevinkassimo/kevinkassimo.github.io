---
layout: post
date: 2017-08-11
title: A Look Into ExpressJS' Source Code (1)
commentLink: https://github.com/kevinkassimo/kevinkassimo.github.io/issues/2
---

## Introduction
ExpressJS is one of the most used NodeJS framework for web application and routing ever since its release. As noted on its [official website](http://expressjs.com/), it has the reputation of being a "fast, unopinionated, minimalist web framework." Created by TJ Holowaychuk (who later shifted to the development of [Koa.js](http://koajs.com) (which we will be reviewing next to see the difference between it and Express)) and currently maintained by Doug Wilson. The current release is Express 4.15.3. However, we will be focusing on the [master branch on Github](https://github.com/expressjs/express/tree/master).

## Layout
The current layout of the project is given in the following graph:
```
- lib
  |
  |-- application.js
  |-- express.js
  |-- request.js
  |-- response.js
  |-- utils.js
  |-- view.js
  |__ router
      |
      |-- index.js
      |-- route.js
      |__ layer.js
```
Our analysis of the source code would start from `router` section.

## Router
The `router` section could in fact be considered a somehow more independent section, as it is even having its [own repository](https://github.com/pillarjs/router) outside of the overall ExpressJS project. To start, we would see what is inside each of its components.

### layer.js
In this file, the usually not-documented class of `Layer` is defined. We can understand a `Layer` as a unit of operation. For instance, when we use `app.use(...)` or `router.use(...)` and provide with multiple middleware functions, we are actually adding multiple layers onto the stack contained inside of each. In the `router` case, there is a property `router.stack` defined. Notice in the lines defining `proto.use` (which is in fact the actual `router.use` we are exposed with), we see the following code:
```javascript
for (var i = 0; i < callbacks.length; i++) {
    var fn = callbacks[i];
    //...
    var layer = new Layer(path, {
        sensitive: this.caseSensitive,
        strict: false,
        end: false
    }, fn);
    layer.route = undefined;
    this.stack.push(layer);
}
```
Here, any callbacks supplied to `router.use(...)` is simply pushed onto the `stack`.  

`Layer` takes in a path, options and an operation function as its component. At first, `path` is not stored in `layer.path`, but in `layer.regexp`. This is due to that Express supports `/login/:user/:id` like expression, for simple `:user => username` variable value storing feature. Thus, using `Regexp` for grouping and mapping becomes handy. Later, `Layer` provides `.match(path)` method. By executing `layer.match(path)`, we compare the given `path` with `this.regexp` to see if this layer actually matches the path, and such that it should function only to certain paths. During the process, each `:user` like expression is matched and having their value stored in `layer.params['user']` for later usage.  

Another notable thing seen in `Layer` is that each layer could function either for `.handle_error()` or `.handle_request()`, but not both. If the handler fails or encounters the wrong task (such as asking a `.handle_request()` only layer to handle error), it would fallback using the provided `next`, which is an argument supplied when calling the one of the two handlers.

### route.js
In this file, the `Route` is defined. Initialized with `new Route(path)`, it correspond to operations (there is an interal `this.stack` where layers would be pushed onto), accepted methods (such as GET, POST, etc.) on a single non-regexp matching route. It is useful in terms that you wants to add multiple methods to different paths with initial part the same.  

Internally, all methods are stored in lowercase, while when using `Route._options()` to access them, they would all be adapted to uppercase versions, with "HEAD" and "GET" usually binding together (when GET is available, HEAD is usually implied). `Route` has all the `.all() .get() .post()...` styled methods, with specific methods defined through an internal loop, and `.all()` implemented with a special internal variable `route._all` property set to `true`.  

A core method of `Route` is `Route.dispatch()`, which is usually not documented.  
```javascript
Route.prototype.dispatch = function dispatch(req, res, done) {
    //...
}
```
This `.dispatch()` method is the essence of `Route`: it takes in normal `req` and `res`, with an additional `done` function passed in to serve finalization (or final error handling if `done` supports a single `err` parameter). It sets the `req.route` to itself, and then loop through each layer on `this.stack` through `next()` chaining, while checking if the request has the same method to the `layer.route`, and conditionally invoke request or error handler (as mentioned in `Layer` above) depending on if some error is present. In simpler terms, `.dispatch()` is the actual method that, when called, would do all the services added through `.get()` like methods. One interesting observation is that if one layer encounters the unexpected type of handler, it would just *silently* call chained `next()` and pass (if present) errors to the next layer, hoping that it could handle it. When the chain of `next()` is completed, the `done(?err)` is invoked to finalize.  

### route/index.js
The actual definition of `express.Router` is specified in this file, with the assistance of `layer.js` and `route.js`.  

The major part of the definition of `router` methods is encapsulated through `proto`, prototype of `router`, which have the following interesting relationship creation:  
```javascript
var proto = module.exports = function(options) {
    //...
    function router(req, res, next) {
        router.handle(req, res, next);
    }
    // mixin Router class functions
    setPrototypeOf(router, proto)

    //...
    return router;
}
```
The `setPrototypeOf` does the `router.__proto__ = proto` trick. `proto` defines all prototypal methods for `router`, while encapsulating the function invocation of `router()` as a synonym for `router.handle()` (we will examine below) for simpler API. In this section, I would use `proto.method()` interchangeably with `router.method()` (which are recorded in documentations), as they are in essence the same thing.  

`proto.use()` is very similar to the method handlers (such as `route.get()`) mentioned before, and is implemented similarly internally. `proto.route()` spins off an independent `Route` out of original router, and registers the `route.dispatch()` method as the callback inside a `Layer`, which is pushed on the main `proto.stack`. In this way, the route is treated and has its callback invoked as a single unit, with all complications wrapped inside of it, where more detailed `Layer` are specified. Nice design!  

`proto.param(name, callback)` (where `callback = function(?req, ?res, ?next, ?paramVal, ?paramName)`) adds callback triggers so that when the specified parameter (as in Express-styled paths `:user`, where `':'` is not needed when provided as an argument to `.param()`) is seen and matched, the callback is invoked. A noticeable part is that this will ALWAYS invoke BEFORE the path-matching callbacks are invoked (e.g. when seeing `/path/:user`, the trigger for parameter `user`, added through `proto.param()`,  will be invoked BEFORE the trigger for `/path/:user`), which I will explain in the next paragraph on the core method. `proto.param()` itself is actually also a very simple method. It pushes the given callback to the `proto.params[paramName]` stack. `proto.params` is an internal object that has key of props matching to each registered parameters, with the value of each of them a stack of all callbacks related. Therefore, this also implies that multiple callback triggers could be added to a single parameter. Notice that if the callback function needs the provided `?req, ?res, ?next, ?paramVal, ?paramName`, they must be in the exact sequence (setting undefined or omitting trailing parameters would be okay), as this is how the core method will invoke the callback through `proto.process_params()` (description see below).  

Here comes the core method, `proto.handle(req, res, out)`. Its status and mechanism is a bit similar to the `route.dispatch()`. First, it stashes some properties of `req`, which will be automatically recovered when the `done()` (a finalizing function created by processing `out`) is called. And then comes the difference from `route.dispatch()`: though `next()` chaining still exists, an internal `while` loop is also present to help examine each layer on `proto.stack`. In these `while` loops, `req.path` is first matched using `layer.match()`. If a match exists, layer would check if itself supports `req.method`. If this is true again, the `while` loop would stop, and later handling steps follows. During this process, the OPTIONS method is specially taken care of with relevant handling functions called. In this way, each matching layers would be used one by one. For the actual handling steps, we first have `proto.process_params(layer, called, req, res, done)`, a method that manages to call each collection of callbacks on parameters without repeating and leaves records of all parameters that have their callbacks invoked in `called`. The actual `layer.handle_request(req, res, next)` that works on the real request handling, only appears in the definition of `done()` here, which would be called only after all parameters have their callbacks invoked. This explains why all parameter callbacks goes before path layer callbacks. After all these have been completed, the `next()`, placed in `layer.handle_request(req, res, next)` this time, is finally called, continues to follow the rest of the `proto.stack` in hopes of getting more matchs. This core method is indeed a complex beast, and the mixed coding style from multiple contributers further obscures the intention behind the lines. Nevertheless, when breaking down in descriptive language, we find its logic still very straightforward, as elegant as it might be.  


### What's Next?
In the next blog post, I will examine other files and components of the ExpressJS framework. The `router` section analyzed in this post could be understood as a miniature of the ExpressJS, as we will see familiar structure in the construction of `app`.
