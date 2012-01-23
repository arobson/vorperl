%%% @author Alex Robson
%%% @copyright Alex Robson, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 16, 2012 by Alex Robson

-module(amqp).

-behavior(gen_server).

-export([
	bind/3, 
	exchange/1,
	exchange/2,
	queue/1,
	queue/2,
	send/2, 
	send/3]).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("amqp_client.hrl").

-include("amqp.hrl").

-define(SERVER, ?MODULE).

-record(state, {
	router, 
	subscriptions}).

%%===================================================================
%%% API
%%===================================================================

bind( Source, Destination, Topic ) ->
	gen_server:cast(?SERVER, {
		bind, 
		Source, 
		Destination, 
		Topic}).

% default exchange
exchange(Exchange) ->
	exchange(Exchange, []).

% configured exchange
exchange(Exchange, Options) ->
	Parsed = amqp_util:parse_proplist(Options),
	gen_server:cast(?SERVER, {
		create_exchange, 
		amqp_util:to_bin(Exchange), 
		Parsed
	}).

queue(Queue) ->
	queue(Queue, []).

queue(Queue, Options) ->
	Parsed = amqp_util:parse_proplist(Options),
	gen_server:cast(?SERVER, {
		create_queue, 
		amqp_util:to_bin(Queue), 
		Parsed
	}).

send(Exchange, Message) ->
	send(
		amqp_util:to_bin(Exchange), 
		Message, 
		#message_flags{}
	).

send(Exchange, Message, Flags) ->
	gen_server:cast(?SERVER, {send, 
		amqp_util:to_bin(Exchange), 
		Message, 
		Flags}).

%%===================================================================
%%% gen_server
%%===================================================================

start_link() ->
	gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
	Router = fun(X)-> 
			io:format("acking message~n"),
			Ack = X#envelope.ack,
			Ack()
		end,
	{ok, #state{router=Router}}.

handle_call(stop, _From, State) ->
  {stop, normal, stopped, State};
 
handle_call(state, _From, State) ->
  {reply, State, State};
 
handle_call(_Request, _From, State) ->
  {reply, ok, State}.
 
handle_cast({create_exchange, Exchange, ExchangeConfig}, State) ->
  {noreply, declare_exchange(Exchange, ExchangeConfig, State)};

handle_cast({create_queue, Queue, QueueConfig}, State) ->
  {noreply, declare_queue(Queue, QueueConfig, State)};

handle_cast({bind, Source, Target, Topic}, State) ->
	{noreply, bind(
		amqp_util:to_bin(Source), 
		amqp_util:to_bin(Target), 
		amqp_util:to_bin(Topic), 
		State)};

handle_cast({send, Exchange, MessageBody, Flags}, State) ->
	{noreply, send_message(Exchange, MessageBody, Flags, State)};

handle_cast(_Msg, State) ->
  {noreply, State}.
 
handle_info(_Info, State) ->
  {noreply, State}.
 
terminate(_Reason, _State) ->
  ok.
 
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%%===================================================================
%%% Internal
%%===================================================================

bind(Source, Target, RoutingKey, State) ->
	Channel= connection_pool:get_channel(control),
	Binding = #'queue.bind'{
		queue=Target, 
		exchange=Source, 
		routing_key=RoutingKey},
	amqp_channel:call(Channel, Binding),
	State.

declare_exchange(Exchange, Config, State) -> 
	Declare = #'exchange.declare'{
		exchange=Exchange,
		type=proplists:get_value(type, Config, <<"direct">>),
		durable=proplists:get_value(durable, Config, false),
		auto_delete=proplists:get_value(auto_delete, Config, false),
		passive=proplists:get_value(passive, Config, false),
		internal=proplists:get_value(internal, Config, false),
		nowait=proplists:get_value(nowait, Config, false)
	},
	Channel= connection_pool:get_channel(control),
	amqp_channel:call(Channel, Declare),
	State.

declare_queue(Queue, Config, State) ->
	Declare = #'queue.declare'{
		queue=Queue,
		exclusive=proplists:get_value(exclusive, Config, false),
		durable=proplists:get_value(durable, Config, false),
		auto_delete=proplists:get_value(auto_delete, Config, false),
		passive=proplists:get_value(passive, Config, false),
		nowait=proplists:get_value(nowait, Config, false)
	},
	Channel = connection_pool:get_channel(control),
	amqp_channel:call(Channel, Declare),
	io:format("Queue ~p declared~n", [Queue]),
	% subscribe
	QueueChannel= connection_pool:get_channel(Queue),
	subscription_sup:start_subscription(Queue, State#state.router, QueueChannel),
	
	State.

encode_message(_Flags, Msg) ->
	amqp_util:to_bin(Msg).

send_message(Exchange, Message, Flags, State) ->
	Channel= connection_pool:get_channel(send),
	Payload = encode_message(Flags, Message),
	{Props, Publish} = amqp_util:prep_message(Exchange, Flags),
	Envelope = #amqp_msg{props = Props, payload = Payload},
	amqp_channel:cast(Channel, Publish, Envelope),
	State.