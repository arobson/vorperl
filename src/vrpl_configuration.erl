%%% @author Alex Robson
%%% @copyright 2014
%%% @doc
%%%		Manage configuration properties for connections, exchanges and queues.
%%% @end
%%% @license MIT
%%% Created January 26, 2014 by Alex Robson

-module(vrpl_configuration).

-behavior(gen_server).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([
	get_broker/0, 
	get_broker/1,
	get_exchange/1,
	get_exchange/2,
	get_queue/1,
	get_queue/2,
	get_serializer/1,
	store_broker/1, 
	store_broker/2,
	store_exchange/2,
	store_queue/2,
	store_serializer/2
	]).

-record(state, {}).

-define(DEFAULT, "default").
-define(TABLE, vrpl_config).
-define(SERVER, ?MODULE).

%% ===================================================================
%%  API
%% ===================================================================

%% all gets go directly against the ETS calls
%% since tables are set for concurrent reads
get_broker() -> lookup_config(?DEFAULT).

get_broker(Broker) -> lookup_config(Broker).

get_exchange(ExchangeName) -> lookup_config(?DEFAULT, exchange, ExchangeName).

get_exchange(Broker, ExchangeName) -> lookup_config(Broker, exchange, ExchangeName).

get_queue(QueueName) -> lookup_config(?DEFAULT, queue, QueueName).

get_queue(Broker, QueueName) -> lookup_config(Broker, queue, QueueName).

get_serializer(ContentType) -> lookup_config(serializer, ContentType).

%% all storage calls should be serialized, hence the use
%% of a simple gen_server
store_broker(Config) -> cast({store, {?DEFAULT, Config}}).

store_broker(Broker, Config) -> cast({store, {Broker, Config}}).

store_exchange(ExchangeName, Config) -> 
	Broker = proplists:get_value(broker, Config, ?DEFAULT),
	cast({store, {Broker, exchange, ExchangeName, Config}}).

store_queue(QueueName, Config) -> 
	Broker = proplists:get_value(broker, Config, ?DEFAULT),
	cast({store, {Broker, queue, QueueName, Config}}).

store_serializer(ContentType, Serializer) ->
	cast({store, {serializer, ContentType, Serializer}}).

cast(Message) -> gen_server:cast(?SERVER, Message).

%%===================================================================
%%% gen_server
%%===================================================================

start_link() ->
	gen_server:start_link({local,?SERVER}, ?MODULE, [], []).

init([]) ->
	init_ets(),
	{ok, #state{}}.

handle_call(stop, _From, State) ->
  {stop, normal, stopped, State};
 
handle_call(_Request, _From, State) ->
  {reply, ok, State}.
 
handle_cast({store, {Broker, Config}}, State) ->
	store_config(Broker, Config),
	{noreply, State};

handle_cast({store, ContentType, Serializer}, State) ->
	store_config(serializer, ContentType, Serializer),
	{noreply, State};

handle_cast({store, {Broker, Primitive, Name, Config}}, State) ->
	store_config(Broker, Primitive, Name, Config),
	{noreply, State};

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.
 
terminate(_Reason, _State) ->
  ok.
 
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%% ===================================================================
%%  ETS
%%  Wrappers for interactions with ETS. Configuration information
%%  for connections, exchanges, queues, etc is static and shouldn't be
%%  lost. This is, perhaps, not the best use of the 
%%  error kernel pattern, but it's an improvement over what I had 
%%  previously.
%% ===================================================================

init_ets() ->
	case ets:info(?TABLE) of
		undefined ->
			ets:new(?TABLE, [ordered_set, public, named_table, {read_concurrency, true}]);
		_ -> ok
	end,
	[ store_config(serializer, ContentType, Serializer) 
		|| {ContentType, Serializer} <- vrpl_message_util:default_serializers() ].

lookup_config(Name) ->
	case ets:lookup(?TABLE, {broker, Name}) of
		[] -> [];
		[{_, Broker}] -> Broker
	end.

lookup_config(serializer, ContentType) ->
	case ets:lookup(?TABLE, {serializer, ContentType}) of
		[] -> undefined;
		[{_, Serializer}] -> Serializer
	end.

lookup_config(Broker, Type, Name) ->
	case ets:lookup(?TABLE, {Broker, Type, Name}) of
		[] -> undefined;
		[{_, Config}] -> Config
	end.

store_config(Broker, Config) -> 
	% Props = amqp_util:broker_declare(Config),
	ets:insert(?TABLE, {{broker, Broker}, Config}).

store_config(serializer, ContentType, Serializer) ->
	ets:insert(?TABLE, {{serializer, ContentType}, Serializer}).

store_config(Broker, Type, Name, Config) -> ets:insert(?TABLE, {{Broker, Type, Name}, Config}).
