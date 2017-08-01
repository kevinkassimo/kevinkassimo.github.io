---
layout: post
date: 2017-08-11
title: A Look Into ExpressJS' Source Code
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
In this file, the class of `Layer` is defined. We can understand a `Layer` as a unit of operation. For instance, when we use `app.use(...)` or `router.use(...)` and provide with multiple middleware functions, we are actually adding multiple layers onto the stack contained inside of each. In the `router` case, there is a property `router.stack` defined. Notice in the lines defining `proto.use` (which is in fact the actual `router.use` we are exposed with), we see the following code:
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
TODO: add review on the `router` section of ExpressJS
