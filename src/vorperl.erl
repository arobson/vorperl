%%% @author Alex Robson
%%% @copyright Alex Robson, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 16, 2012 by Alex Robson

-module(vorperl).

-behavior(gen_server).

-export([
	bind/3,
	broker/0,
	broker/1, 
	content_provider/3,
	exchange/1,
	exchange/2,
	queue/1,
	queue/2,
	route_to/1,
	send/2, 
	send/3,
	send/4,
	stop_subscription/1,
	subscribe_to/1,
	subscribe_to/2,
	topology/3
	]).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("amqp.hrl").

-define(SERVER, ?MODULE).

-record(state, {
	router, 
	control_channel,
	content_providers = dict:new(),
	declarations = [],
	queues = dict:new(),
	subscriptions = dict:new()}).

%%===================================================================
%%% API
%%===================================================================

bind( Source, Destination, Topic ) ->
	gen_server:cast(?SERVER, {
		bind, 
		Source, 
		Destination, 
		Topic}).

broker() ->
	connection_pool:add_broker().

broker(Props) ->
	connection_pool:add_broker(Props).

content_provider( ContentType, Encoder, Decoder ) ->
	gen_server:cast(?SERVER, {ContentType, Encoder, Decoder}).

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

route_to(Router) ->
	gen_server:cast(?SERVER, {
		route,
		Router
	}).

send(Exchange, Message) ->
	send(
		Exchange, 
		Message, 
		""
	).

send(Exchange, Message, RoutingKey) ->
	send(
		Exchange, 
		Message,
		RoutingKey, 
		[]
	).

send(Exchange, Message, RoutingKey, Properties) ->
	gen_server:cast(?SERVER, {
		send, 
		amqp_util:to_bin(Exchange), 
		Message,
		amqp_util:to_bin(RoutingKey), 
		Properties
	}).

stop_subscription(Queue) ->
	gen_server:cast(?SERVER, {
		stop_subscription,
		amqp_util:to_bin(Queue)
	}).

subscribe_to(Queue) ->
	gen_server:cast(?SERVER, {
		subscribe,
		amqp_util:to_bin(Queue)
	}).

subscribe_to(Queue, RouteTo) ->
	gen_server:cast(?SERVER, {
		subscribe,
		amqp_util:to_bin(Queue),
		RouteTo
	}).

topology({exchange, ExchangeName, ExchangeProps}, 
		 {queue, QueueName, QueueProps}, Topic) ->
	exchange(ExchangeName, ExchangeProps),
	queue(QueueName, QueueProps),
	bind(ExchangeName, QueueName, Topic).

%%===================================================================
%%% gen_server
%%===================================================================

start_link() ->
	gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
	Router = fun(X)-> 
			io:format("Message: ~p ~n", [X#envelope.body]),
			Ack = X#envelope.ack,
			Ack()
		end,
	{ok, #state{
		router=Router,
		content_providers=default_providers()
	}}.

handle_call(stop, _From, State) ->
  {stop, normal, stopped, State};
 
handle_call(state, _From, State) ->
  {reply, State, State};
 
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast({bind, Source, Target, Topic}, State) ->
	{noreply, bind(
		amqp_util:to_bin(Source), 
		amqp_util:to_bin(Target), 
		amqp_util:to_bin(Topic), 
		State)};

handle_cast({content_provider, ContentType, Encode, Decode}, State) ->
	Queues = State#state.queues,
	lists:foreach(
		fun({_,V}) -> queue_subscriber:content_provider(V, ContentType, Encode, Decode) end,
		dict:to_list(Queues)
	),
	{noreply, State#state{ content_providers = 
		dict:store(ContentType, {Encode, Decode}, State#state.content_providers)
	}};

handle_cast({create_exchange, Exchange, ExchangeConfig}, State) ->
  {noreply, declare_exchange(Exchange, ExchangeConfig, State)};

handle_cast({create_queue, Queue, QueueConfig}, State) ->
  {noreply, declare_queue(Queue, QueueConfig, State)};

handle_cast({new_subscription, Queue, Pid}, State) ->
	Ref = monitor(process, Pid),
	{noreply, State#state{
		queues = dict:store(Queue, Pid, State#state.queues),
		subscriptions = dict:store(Ref, Queue, State#state.subscriptions)
	}};

handle_cast({route, RouteTo}, State) ->
	Queues = State#state.queues,
	lists:foreach(
		fun({_,V}) -> queue_subscriber:route_to(V, RouteTo) end,
		dict:to_list(Queues)
	),
	{noreply, State};

handle_cast({send, Exchange, MessageBody, RoutingKey, Props}, State) ->
	{noreply, send_message(Exchange, MessageBody, RoutingKey, Props, State)};

handle_cast({stop_subscription, Queue}, State) ->
	Queues = State#state.queues,
	case dict:is_key(Queue, Queues) of
		true ->
			Pid = dict:fetch(Queue, Queues),
			NewQueues = dict:erase(Queue, Queues),
			queue_subscriber:stop(Pid),
			{noreply, State#state{ queues = NewQueues }};
		_ -> {noreply, State}
	end;

handle_cast({subscribe, Queue}, State) ->
	subscribe(Queue, State#state.router, State),
	{noreply, State};

handle_cast({subscribe, Queue, RouteTo}, State) ->
	subscribe(Queue, RouteTo, State),
	{noreply, State};

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info({'DOWN', Ref, process, _Pid, Info}, State) ->
	Subscriptions = State#state.subscriptions,
	case dict:is_key(Ref, Subscriptions) of
		false ->
			if 
				Info =:= shutdown ->
					io:format("Shutting down normally.~n"),
					{noreply, State};
				true ->
					io:format("Control channel shutdown with ~p ~n", [Info]),
					Channel = connection_pool:get_channel(control),
					replay_declarations(State#state.declarations, Channel, State),
					{noreply, State#state{ 
						control_channel = monitor(process, Channel) }}
			end;
		true ->
			Queue = dict:fetch(Ref, Subscriptions),
			Queues = State#state.queues,
			NewQueues = 
				case dict:is_key(Queue, Queues) of
					true -> dict:erase(Queue, Queues);
					false -> Queues
				end,
			{noreply, State#state{ 
				subscriptions = dict:erase(Ref, Subscriptions),
				queues = NewQueues
			}}
	end;

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
	State2 = State#state{ declarations =
		lists:append(State#state.declarations, [{bind, Binding}])},
	ensure_monitor(Channel, State2).

declare_exchange(Exchange, Config, State) -> 
	Declare = amqp_util:exchange_declare(Exchange, Config),
	Channel= connection_pool:get_channel(control),
	amqp_channel:call(Channel, Declare),
	State2 = State#state{ declarations =
		lists:append(State#state.declarations, [{exchange, Declare}])},
	ensure_monitor(Channel, State2).

declare_queue(Queue, Config, State) ->
	Declare = amqp_util:queue_declare(Queue, Config),
	Channel = connection_pool:get_channel(control),
	Router = proplists:get_value(route_to, Config, State#state.router),
	amqp_channel:call(Channel, Declare),
	subscribe(Queue, Router, State),
	State2 = State#state{ 
		declarations = 
			lists:append(State#state.declarations, [{queue, Queue, Declare, Router}])},
		
	ensure_monitor(Channel, State2).

default_providers() ->
	Json_Coders = { 
		fun(X) -> message_util:json_encode(X) end,
		fun(X) -> message_util:json_decode(X) end 
	},
	Bert_Coders = {
		fun(X) -> message_util:bert_encode(X) end,
		fun(X) -> message_util:bert_decode(X) end 			
	},
	dict:from_list([
		{"application/json", Json_Coders },
		{<<"application/json">>, Json_Coders },
		{"application/x-erlang-binary", Bert_Coders },
		{<<"application/x-erlang-binary">>, Bert_Coders }
	]).

encode_message(Msg, Flags, State) ->
	Providers = State#state.content_providers,
	ContentType = proplists:get_value(content_type, Flags, <<"plain/text">>),
	case dict:is_key(ContentType, State#state.content_providers) of
		true -> 
			{Encoder, _} = dict:fetch( ContentType, Providers ),
			Encoder(Msg);
		_ -> amqp_util:to_bin(Msg)
	end.

ensure_monitor(Channel, State) ->
	State#state{ control_channel = 
		case State#state.control_channel of
			undefined -> monitor(process, Channel);
			_ -> State#state.control_channel
		end }.

replay_declarations([], _Channel, _State) ->
	ok;
replay_declarations([D|T], Channel, State) ->
	replay_declarations(D, Channel, State),
	replay_declarations(T, Channel, State);

replay_declarations({queue, Queue, Declaration, Router}, Channel, State) ->
	amqp_channel:call(Channel, Declaration),
	subscribe(Queue, Router, State);

replay_declarations({_Type, Declaration}, Channel, _State) ->
	amqp_channel:call(Channel, Declaration).

send_message(Exchange, Message, RoutingKey, Props, State) ->
	Channel= connection_pool:get_channel(send),
	Payload = encode_message(Message, Props, State),
	{AmqpProps, Publish} = amqp_util:prep_message(Exchange, RoutingKey, Props),
	Envelope = #amqp_msg{props = AmqpProps, payload = Payload},
	amqp_channel:cast(Channel, Publish, Envelope),
	State.

subscribe(Queue, Router, State) ->
	QueueChannel = connection_pool:get_channel(Queue),
	subscription_sup:start_subscription(
		Queue, 
		Router, 
		QueueChannel, 
		State#state.content_providers).