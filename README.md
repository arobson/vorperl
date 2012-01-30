# Vorperl

RabbitMQ is amazing. I love it. I have a rabbit shaped hammer and everything looks like a carrot-nail. 

Unfortunately the rabbit-erlang-client API is real world implementation of a jabberwocky and you need to tame it. You need vorperl.

Vorperl is near beta (in that it supports a decent baseline functionality). Please do not attempt to slay production jabberwockies at this time.

## How To Use

I would recommend pulling it into your project using a rebar dependency section.

	{vorperl, "0.0.*",
   		{git, "git://github.com/arobson/vorperl",
		{branch, "master"} } }, 

It also needs to have started before your code calls it. Do this by listing it in your {project}.app.src file in the applications tuple (after sasl).

{applications, [
		kernel,
		stdlib,
		sasl,
		lager, % You're not using lager? Do you hate readability?
		vorperl % See? Simple-ish
	]}

## Examples

For now, these examples assume you're playing from the shell. If you want an easy way to do that, pull the repo down, run rebar compile and then run dev_start.sh.

### Step 1 - Connect to a broker
You always have to do this first. If you don't you'll get a lovely crash dump. I'll improve that one day, but for now, how 'bout just remember you have to connect first.

	%connects you to a local rabbitmq broker with defaults
	vorperl:broker(). 

	% otherwise you can provide your own settings using a proplist
	% connection settings are shown to document the atoms for each property
	vorperl:broker([
		{host, "192.168.1.1"},
		{port, 8998},
		{user, "SirRobin"},
		{password, "RunAwayMore"},
		{virtual_host, "Caerbannog"}
	]).

### Step 2 - Declare Topology
You can create exchanges, queues and bindings as follows:

	%simple exchange declaration with defaults
	
	vorperl:exchange("ex1", []).


	% high maintenance exchange declaration
	% Note: single atoms are expanded to {atom, true}
	% Note: all these flags are not a valid combination
	% 		and are only included to show what's available

	vorperl:exchange("ex1", [
		{type, "topic"},
		durable,
		auto_delete,
		passive,
		internal,
		nowait
	]).

	%simple queue declaration with defaults

	vorperl:queue("q1", []).


	%% Same idea as exchange declaration

	vorperl:queue("q1", [
		exclusive,
		durable,
		auto_delete,
		passive,
		nowait,
		{route_to, Route} % Can be fun(X), Pid or {Module, Function}
	]).

	%% binding a queue to exchange

	vorperl:bind("x1", "q1", ""). % matches all keys

	vorperl:bind("x1", "q1", "*"). % matches all keys with 1 term

	vorperl:bind("x1", "x2", ""). % binds exchange 'x2' to exchange 'x1'


### Step 3 - Declare Topology In A Single Call
You can declare an exchange, a queue and bind them together all in one call

	vorperl:topology(
		{exchange, "x1", [auto_delete]}, % a direct exchange marked as auto delete
		{queue, "q1", [auto_delete]}, % a queue marked as auto delete
		"" % a blank topic used for the binding
	).

### Step 4 - Setting The Router
The default message handler for all subscriptions is unhelpful and simply prints the message and then acks it. You can change this by providing your own fun/1, Pid or MFA signature.

Currently, calling route_to resets the router for all active queues and changes the default.

	vorperl:route_to(fun(X) -> io:format("this is a waste!~n") end).

	vorperl:route_to(AGenServerPid).

	vorperl:route_to({Module, Function}).

### Step 5 - Sending Messages For Fun and Profit
Sending a message is simple-ish.

	vorperl:send("x1", "message").

	vorperl:send("x1", "message", "routing.key").

	vorperl:send("x1", "message", "routing.key",[
		{content_type, "plain/text"},
		{content_encoding, "binary"},
		{correlation_id, "1"},
		{id, "1"},
		persist, % this flag causes the message to get stored to disk if needed
		mandatory,
		immediate,
		{reply_to, "exchange"},
		{expiration, Date},
		{timestamp, Timestamp},
		{user_id, User},
		{app_id, App},
		{cluster_id, Cluster},
		{priority, Priority}
	]).

### Step 6 - Processing Messages
vorperl wraps the message in a meta-data rich envelope. You'll need to include the "amqp.hrl" file from the include folder. The record type, predictably, is envelope.

	% behold, the envelope record...
	#envelope{
			exchange,
			queue,
			key,
			body, % the actual message you received
			correlation_id,
			content_type,
			content_encoding,
			type,
			headers,
			id,
			timestamp,
			user_id,
			app_id,
			cluster_id,
			ack,
			nack
		}

	% note the ack and nack fields
	% these fields contain a fun/0 that will ack/nack this particular
	% message on the broker

### Feature - Subscribe to Queue
Vorperl currently automatically subscribes to every queue you declare. For topologies where the queue is already declared or in cases where you may want to start/stop subscriptions, you can call one of the subscribe functions:

	% subscribe to a queue
	vorperl:subscribe_to("q1").

	% subscribe to a queue and provide a custom route target
	vorperl:subscribe_to("q1", Route). % fun(X), Pid or {M, F}

## Feature -- Stop Subscription

	% stop subscription
	vorperl:stop_subscription("q1").

## Feature -- Define Encoder / Decoder by Content Type
RabbitMQ allows you to set a content type on messages which will be provided on incoming messages via the envelope record. Vorperl will attempt to encode and decode the message body based on built in or custom encoder / decoder functions.

The built-in encoder / decoder pairs exist only for plain/text, application/x-erlang-binary and application/json.

	% adding support for a new content-type
	Encoder = fun(X) -> %do something and return binary result% end,
	Decoder = fun(X) -> %decode binary to Erlang representation% end,
	vorperl:content_type(<<"application/custom">>, Encoder, Decoder).

## Contributions
It would be really cool to get suggestions or feature requests but it would be infinite orders of magnitude cooler to get pull requests.

## To Do
 *	Add Mocks and Unit Tests.
 *	Provide examples
 *  Provide callback/proccess for response handling
 *  Provide event handler to publish messages to an exchange



## License
MIT / GPL

## Disclaimer

There are no unit tests so your confidence in this project should take that into consideration. Don't B h8n' though, I plan to add them. Testing this kind of thing is rather difficult since most of it is just interacting with I/O and I'm unfamiliar with mocking approaches in Erlang.

I am not in my right mind, but I do enjoy writing software and posting it to github where it can be promptly ignored.