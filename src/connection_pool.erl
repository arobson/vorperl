%%% @author Alex Robson
%%% @copyright Alex Robson, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 20, 2012 by Alex Robson

-module(connection_pool).

-behavior(gen_server).

-export([ start_link/0, add_broker/0, add_broker/1, get_channel/1, get_channel/2]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-include("amqp.hrl").

-include("amqp_client.hrl").

-record(state, {brokers=dict:new(), channels=dict:new()}).

%%===================================================================
%%% API
%%===================================================================

add_broker() ->
	add_broker(#broker{}).

add_broker(Broker=#broker{}) ->
	gen_server:call(?SERVER, {broker, amqp_util:broker_to_bin(Broker)}).

get_channel(Key) ->
	gen_server:call(?SERVER, {channel, Key}).

get_channel(Broker, Key) ->
	gen_server:call(?SERVER, {channel, Broker, Key}).

%%===================================================================
%%% gen_server
%%===================================================================

start_link() ->
	gen_server:start_link({local,?SERVER}, ?MODULE, [], []).

init([]) ->
	{ok, #state{}}.

handle_call(stop, _From, State) ->
  {stop, normal, stopped, State};
 
handle_call(state, _From, State) ->
  {reply, State, State};
 
handle_call({broker, Broker}, _From, State) ->
	{_, State2} = create_connection_for(Broker, State),
	{reply, ok, State2};

handle_call({channel, Key}, _From, State) ->
	{Channel, State2} = get_channel_for(Key, State),
	{reply, Channel, State2};

handle_call({channel, Broker, Key}, _From, State) ->
	{Channel, State2} = get_channel_for(Broker, Key, State),
	{reply, Channel, State2};

handle_call(_Request, _From, State) ->
  {reply, ok, State}.
 
handle_cast(_Msg, State) ->
  {noreply, State}.
 
handle_info(_Info, State) ->
  {noreply, State}.
 
terminate(_Reason, _State) ->
  ok.
 
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

to_connection(Broker) ->
	#amqp_params_network{
		username = Broker#broker.user,
		password = Broker#broker.password,
		virtual_host = Broker#broker.virtual_host,
		port = Broker#broker.port,
		host = Broker#broker.host,
		channel_max = Broker#broker.max_channels,
		frame_max = Broker#broker.max_frames,
		heartbeat = Broker#broker.heartbeat,
		connection_timeout = infinity,
		ssl_options = Broker#broker.ssl_options
	}.

create_connection_for(Broker, State) ->
	case amqp_connection:start(to_connection(Broker)) of
		{ok, Connection} ->
			NewBroker = Broker#broker{ connection = Connection },
			Brokers = dict:store(Broker#broker.name, NewBroker, State#state.brokers),
			{Connection, State#state{ brokers = Brokers } };
		_ -> {undefined, State}
	end.

get_connection_for(Broker, State) ->
	Alive = case is_pid(Broker#broker.connection) of
		true -> is_process_alive(Broker#broker.connection);
		_ -> false
	end,
	case Alive of
		true -> {Broker#broker.connection, State};
		_ -> create_connection_for(Broker, State)
	end.

get_connection(Broker, State) ->
	Brokers = State#state.brokers,
	B = dict:fetch(Broker, Brokers),
	get_connection_for(B, State).

create_channel(Connection) ->
	case amqp_connection:open_channel(Connection) of
		{ok, Channel} -> Channel;
		_ -> undefined
	end.

add_channel(Broker, Key, State) ->
	Channels = State#state.channels,
	{Connection, State2} = get_connection(Broker, State),
	Channel = create_channel(Connection),
	State3 = State2#state{ channels = dict:store(Key, Channel, Channels)},
	{Channel, State3}.

get_channel_for(Key, State) ->
	[Broker | _ ] = dict:fetch_keys(State#state.brokers),
	get_channel_for(Broker, Key, State).

get_channel_for(Broker, Key, State) ->
	Channels = State#state.channels,
	case dict:is_key(Key, Channels) of
		true ->
			StoredChannel = dict:fetch(Key, Channels),
			case is_process_alive(StoredChannel) of
				true -> {StoredChannel, State};
				_ -> add_channel(Broker, Key, State)
			end;
		_ ->
			add_channel(Broker, Key, State)		
	end.

