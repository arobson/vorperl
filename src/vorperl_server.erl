%%% @author Alex Robson
%%% @copyright appendTo, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 16, 2012 by Alex Robson

-module(vorperl_server).

-behavior(gen_server).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("amqp.hrl").

-define(SERVER, ?MODULE).

-compile([export_all]).

-record(state, {
	router, 
	control_channel,
	content_providers = dict:new(),
	declarations = [],
	queues = dict:new(),
	subscriptions = dict:new()}).

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
		content_providers=message_util:default_providers()
	}}.

handle_call(stop, _From, State) ->
	{stop, normal, stopped, State};
 
handle_call(state, _From, State) ->
	{reply, State, State};

handle_call(list_content_providers, _From, State) ->
	{reply, State#state.content_providers, State};
 
handle_call(_Request, _From, State) ->
	{reply, ok, State}.

handle_cast({bind, Source, Target, Topic}, State) ->
	{noreply, bind(
		amqp_util:to_bitstring(Source), 
		amqp_util:to_bitstring(Target), 
		amqp_util:to_bitstring(Topic), 
		State)};

handle_cast({content_provider, ContentType, Encode, Decode}, State) ->
	Queues = State#state.queues,
	Type = amqp_util:to_bitstring(ContentType),
	lists:foreach(
		fun({_,V}) -> queue_subscriber:content_provider(V, Type, Encode, Decode) end,
		dict:to_list(Queues)
	),
	{noreply, State#state{ content_providers = 
		dict:store(Type, {Encode, Decode}, State#state.content_providers)
	}};

handle_cast({create_exchange, Exchange, ExchangeConfig}, State) ->
	Ex = amqp_util:to_bitstring(Exchange),
	Props = amqp_util:parse_proplist(ExchangeConfig),
	{noreply, declare_exchange(Ex, Props, State)};

handle_cast({create_queue, Queue, QueueConfig}, State) ->
	Q = amqp_util:to_bitstring(Queue),
	Props = amqp_util:parse_proplist(QueueConfig),
	{noreply, declare_queue(Q, Props, State)};

handle_cast({new_subscription, Queue, Pid}, State) ->
	Q = amqp_util:to_bitstring(Queue),
	Ref = monitor(process, Pid),
	{noreply, State#state{
		queues = dict:store(Q, Pid, State#state.queues),
		subscriptions = dict:store(Ref, Q, State#state.subscriptions)
	}};

handle_cast({route, RouteTo}, State) ->
	Queues = State#state.queues,
	lists:foreach(
		fun({_,V}) -> queue_subscriber:route_to(V, RouteTo) end,
		dict:to_list(Queues)
	),
	{noreply, State#state{router = RouteTo}};

handle_cast({send, Exchange, MessageBody, RoutingKey, MessageProperties}, State) ->
	Ex = amqp_util:to_bitstring(Exchange),
	Body = MessageBody,
	Key = amqp_util:to_bitstring(RoutingKey),
	Props = amqp_util:parse_proplist(MessageProperties),
	{noreply, send_message(Ex, Body, Key, Props, State)};

handle_cast({stop_subscription, Queue}, State) ->
	Q = amqp_util:to_bitstring(Queue),
	Queues = State#state.queues,
	case dict:is_key(Q, Queues) of
		true ->
			Pid = dict:fetch(Q, Queues),
			NewQueues = dict:erase(Q, Queues),
			queue_subscriber:stop(Pid),
			{noreply, State#state{queues = NewQueues}};
		_ -> {noreply, State}
	end;

handle_cast({subscribe, Queue}, State) ->
	Q = amqp_util:to_bitstring(Queue),
	subscribe(Q, State#state.router, State),
	{noreply, State};

handle_cast({subscribe, Queue, RouteTo}, State) ->
	Q = amqp_util:to_bitstring(Queue),
	subscribe(Q, RouteTo, State),
	{noreply, State};

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info({'DOWN', Ref, process, _Pid, Info}, State) ->
	Subscriptions = State#state.subscriptions,
	case dict:is_key(Ref, Subscriptions) of
		false -> handle_channel_shutdown(Info, State);
		true -> handle_subscription_shutdown(Ref, Subscriptions, State)
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

ensure_monitor(Channel, State) ->
	State#state{ control_channel = 
		case State#state.control_channel of
			undefined -> monitor(process, Channel);
			_ -> State#state.control_channel
		end }.

handle_channel_shutdown(Info, State) ->
	if 
		Info =:= shutdown ->
			io:format("Shutting down normally.~n"),
			{noreply, State};
		true ->
			io:format("Control channel shutdown with ~p ~n", [Info]),
			Channel = connection_pool:get_channel(control),
			replay_declarations(State#state.declarations, Channel, State),
			{noreply, State#state{control_channel = monitor(process, Channel)}}
	end.

handle_subscription_shutdown(Ref, Subscriptions, State) ->
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
	}}.

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
	Payload = message_util:encode_message(Message, Props, State#state.content_providers),
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