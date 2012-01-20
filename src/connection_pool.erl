%%% @author Alex Robson
%%% @copyright Alex Robson, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 20, 2012 by Alex Robson

-module(connection_pool).

-behavior(gen_server).

-export([ add_broker/0, add_broker/1, get_channel/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-include("amqp.hrl").

-include("amqp_client.hrl").

-record(state, {brokers=dict:new(), channels=dict:new())}).

%%===================================================================
%%% API
%%===================================================================

add_broker() ->
	add_broker(#broker{}).

add_broker(Broker=#broker{}) ->
	gen_server:call(?SERVER, {broker, amqp_util:broker_to_bin(Broker)}).

get_channel(Key) ->
	gen_server:call(?SERVER, {channel, Key}).

%%===================================================================
%%% gen_server
%%===================================================================

start_link() ->
	gen_server:start_link({local,?SERVER}, ?MODULE, [], []).

init([]) ->
	{ok, #state{}}

handle_call(stop, _From, State) ->
  {stop, normal, stopped, State};
 
handle_call(state, _From, State) ->
  {reply, State, State};
 
handle_call({broker, Broker}, _From, State) ->
	{reply, ok, create_connection_for(Broker, State)};

handle_call({channel, Key}, _From, State) ->
	{reply, ok, get_channel_for(Key, State)};

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

to_connection(#broker{
		user = User,
		password = Password,
		virtual_host = VirtualHost,
		host = Host,
		port = Port,
		max_channels = MaxChannels,
		max_frames = MaxFrames,
		heartbeat = HeartBeat,
		ssl_options = SSL,
		auth = Auth,
		client = Client
	}) ->

	amqp_params_network#{
		user = User,
		password = Password,
		virtual_host = VirtualHost,
		port = Port,
		host = Host,
		channel_max = MaxChannels,
		frame_max = MaxFrames,
		heartbeat = HeartBeat,
		connection_timeout = infinity,
		ssl_options = SSL
	}.

create_connection_for(Broker, State) ->
	case is_process_alive(Broker#broker.connection) of
		true -> {Broker#broker.connection, State};
		_ ->
			Connection = amqp_connection:start(to_connection(Broker)),
			NewBroker = Broker#broker{ connection = Connection },
			Brokers = dict:store(Broker#broker.name, NewBroker, BrokerState#state.brokers,
			{Connection, State#state{ brokers = Brokers } }
	end.

get_connection(State) ->
	Brokers = State#state.brokers,
	BrokerList = dict:fetch_keys(Brokers),
	[K1 | _ ] = BrokerList,
	B = dict:fetch(K1),


get_channel(State) ->
	case amqp_connection:open_channel(Connection) of
		{ok, Channel} -> Channel;
		_ -> undefined
	end.

get_channel_for(Key, State) ->
	Channels = State#state.channels,
	case dict:is_key(Key, Channels) ->
		true -> dict:fetch(Key, Channels);
		_ ->
			


control_channel(State) ->
	case State#state.control_channel of
		undefined -> 
			NewChannel = get_channel(State),
			{NewChannel, State#state{ control_channel=NewChannel}};
		Channel -> {Channel, State}
	end.

connect() ->
	amqp_connection:start(connection_details()).

connection_details() ->
	#amqp_params_network{}.


