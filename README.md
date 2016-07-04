# Sample application demonstrating the current streaming state with Devise or Warden

[Devise](https://github.com/plataformatec/devise) is an authentication library built
on top of [Warden](https://github.com/hassox/warden), providing a seamless integration
with Rails apps. This application was created following the steps described in Devise's
Getting Started section. Take a look at the individual commits and their messages if
you want to check each step.

Warden is a [Rack](http://rack.github.io/)'s middleware and authentication is handled
using a "throw/catch(:warden)" approach. This works fine with Rails
[until streaming is enabled with ActionController::Live](https://github.com/plataformatec/devise/issues/2332).

José Valim [pointed out](https://github.com/plataformatec/devise/issues/2332#issuecomment-14977804)
that the problem is ActionController::Live's fault. This is because the Live module
changes the "process" method so that it runs inside a spawn thread, so that it can
return to finish processing the remaining middlewares in the stack. Nothing is sent
to the connection before leaving that method due to the Rack issue I'll describe
next. But the "process" method will also handle all filters (before/around/after
action hooks). Usually the authentication happens in a before action filter and if
the user is not authentication Devise will `throw :warden` but since this is
running in a spawn thread, the Warden middleware doesn't have the chance to catch
this symbol and handle it properly.

## The Rack issue

I find it amusing that after so many years of web development with Ruby, Rack
doesn't seem to have evolved much to better handling streamed responses, including
SSE and why not websockets. The basic blocks are basically the same as when Rack
was first created in a successful attempt to add a standard API web servers and
frameworks could agree and build on top of it. This is a great achievement but
Rack should evolve to better handle streamed responses.

Aaron Patterson has tried to work on [another API](https://github.com/tenderlove/the_metal)
for Rack that would improve support for streaming but it seems it would break middlewares,
and currently it seems [the metal is dead](http://rebuild.fm/122/). Sounds like
HTTP 2.0 multiplexing requires yet more changes, so maybe we'll get proper support
in Rack 3.0, which should be backward compatible and keep supporting existing middlewares,
by providing alternative APIs, but that seems like it could take years to get there.

Currently, the way Rack applications handle streaming is by implementing an object
that responds to each that will yield a chunk at a time until the stream is finished,
which is usually implemented by providing the user an API similar to a proper stream
object as properly implemented in other languages. A few years ago an alternative
system has been suggested, which became known as the
[hijacking API](http://www.rubydoc.info/github/rack/rack/file/SPEC#Hijacking). The
[Phusion team covered it when it was introduced](http://old.blog.phusion.nl/2013/01/23/the-new-rack-socket-hijacking-api/)
but I think the "partial hijacking" section is no longer valid.

Rack was designed on top of a middleware stack which means any response will only
start after all middlewares have been called and returned (except if hijacking is used),
since middlewares don't have access to the socket stream. That's why Rails had to resort
to using threads to handle streamed/chunked responses. But it can offer other alternative
implementations that would be more friendly to how Warden and Devise work as
demonstrated in this application, which I'll discuss in the next section.

Before talking about Rails current options, I'd like to stress a bit more the
problem with Rack without hijacking, and consequently how it affects web development
in Ruby in a negative way, when compared to how this is done in most other languages.

If we compare to how streaming is handled in Grails (and most JVM based frameworks)
, or most of the main web frameworks in other languages, it couldn't be any simpler.
Each request thread (or process) has access to a "response" object that accepts
a "write" call that goes directly to the socket's output (or after a "flush" call).

There's no need to flag a controller as capable of streaming. They are just regular
controllers. The request thread or process does not have to spawn another thread
to handle streaming, so there's nothing special with such controllers.

It would be awesome if Ruby web applications had the option to use a more flexible
API, more friendly to streamed responses, including SSE and websockets. Hijacking
currently seems to be considered a second-class citizen since they are usually
ignored by major web frameworks like Rails itself.

## The Rails case (or how to work around the current state in Rack apps)

So, with Rails one doesn't flag an action as one requiring streaming support. They
have to flag the full controller. In theory all other actions not taking advantage
of the streaming API should work just like regular controllers not flagged with
ActionController::Live.

The obvious question is then, "so, why isn't Live always included?". After all,
the Rails users wouldn't have to worry about enabling streaming, it would be simply
enabled by default for when you want it. One might think that it would be related
to performance concerns but I suspect that the main problem is that this is not
issues free.

Some middleware assume that the inner middlewares have finished
(some of them actually depend on them to be finished) so that they can modify the
original response or headers. This kind of post-processing middlewares do not work
well with streamed responses.

This includes caching middlewares (handling ETag or
last-modified headers), monitoring middlewares injecting some HTML (like NewRelic
does automatically by default for example) and many other. Those middlewares will
block the stack until the response is fully finished which breaks the desired
streamed output. Some of them will check some conditions and skip this blocking
behavior under certain circumstances but some will still cause some hard to debug
issues or they may be even conceptually broken.

There are also some middlewares that expect the controller's action code to run
in the same thread due to the implementation details surrounding them. For example,
if a sandboxed database environment is implemented as a middleware that runs the
following layer inside a transaction block that will be rolled back, and if the
connection is automatically fetched using the current thread id as the access key,
then spawning a new thread would run in a different connection and out of the
middleware's transaction, breaking the sandboxed environment. I think ActiveRecord
fetches the connection from thread locals and since ActionController::Live will
copy those locals to the new spawned thread it probably works, but I'm just
warning that spawning threads may break several middlewares in unexpected ways.

This includes the behavior of Warden communication. So, enabling Live in all
Rails controllers would have the immediate effect of breaking most current
Rails applications as Devise is the de facto authentication standard for Rails
apps. Warden assumes the code handling authentication checks is running in the
same thread. It could certainly offer another strategy to inform about failed
authentication, but this is not how it currently works.

Even though José Valim said there's nothing they could do because it's Live's
fault, this is not completely true. I guess he meant that it would be too much
work to make it work. After all, we can't simply put the fault on Live since
the fault actually lies in Rack itself, so streaming is fundamentally broken.

Devise could certainly subclass Warden::Manager and use this subclass as its
middleware and overwrite "call" to add some object to env, for example, that
would listen to reported failures and they could replace "throw :warden" in
its own code with a more higher level API that would communicate to warden
properly. But I agree this is a mess and probably doesn't worth, specially
because it couldn't be called exactly Warden compatible. Another option could
be to change Warden itself so that it doesn't expect the authentication checks
to happen in the same thread. Or it could replace the "throw-catch" approach
with a "raise/rescue" one, which should work out of the box to how Rails
currently handles it. It shouldn't be hard for Devise itself to wrap Warden
and use Exceptions rather than throw-catch, but again, I'm not sure if this
is really worthy.

So, let's explore other options, which adds other API options to Rails itself.

### A suggestion to add a new API to Rails

The Warden case is a big issue since Devise is very popular among Rails apps
and shouldn't be ignored. Usually the authentication is performed in filters
rather than in the action itself. Introducing a new API would give the user
the chance of performing authentication in the main request thread before
spawning the streamed thread. This works even if the authentication check is
done directly in the action rather than in the filters. The API would work
something like:

```ruby
def my_action
  # optionally call authenticate_user! here, if not using filters
  streamed do |stream|
    3.times{stream.write "chunk"; sleep 1}
  end
end
```

This way, the thread would only be spawned after the authentication check is
finished. Or `streamed` could use `env['rack.hijack']` when available instead
of spawning a new thread.

### Use Rack hijacking

Another alternative might be to support streaming only for web servers supporting
Rack hijacking. This way, the stream API could work seamless, without requiring
`ActionController::Live` to be included. When `response.stream` is used, it would
use `env['rack.hijack_io']` if available or either buffer the responses and send
them at once or raise some error, based on some configuration accordingly to the
user's preferences, as sometimes streaming is not only an optimization but a
requirement that shouldn't be silently ignored. The same behavior would apply when
HTTP 1.0 is used for example.

Or another module such as `ActionController::LiveHijacking` could be created so
that Rails users would have that option for a while until Rails thinks this
approach is stable enough to be enabled by default.

## Conclusion

I'd like to propose two discussions around this issue. One would be a better
solution for Rack applications to get to talk directly to the response (
or discussing an strategy for making Rack hijacking a first-class citizen
and probably call it something better than hijack). And
the other solution would be for Rails to improve support for streaming
applications by better handling cases like the Warden/Devise issue. I've
copied this text with some minor changes to [my site](http://rosenfeld.herokuapp.com/en/articles/ruby-rails/2016-07-02-the-sad-state-of-streaming-in-ruby-web-applications)
so that it could be discussed in the Disqus' comments section or we could discuss it in the
issues section of this sample project or in the rails-core mailing list,
your call.
