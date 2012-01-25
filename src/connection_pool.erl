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

-record(state, {brokers=dict:new(), channels=dict:new()}).

%%===================================================================
%%% API
%%===================================================================

add_broker() ->
	add_broker([]).

add_broker(Props) ->
	gen_server:call(?SERVER, {broker, amqp_util:broker_declare(Props)}).

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

add_channel(Broker, Key, State) ->
	Channels = State#state.channels,
	{Connection, State2} = get_connection(Broker, State),
	case create_channel(Connection) of
		retry -> add_channel(Broker, Key, State);
		Channel ->
			State3 = State2#state{ channels = dict:store(Key, Channel, Channels)},
			{Channel, State3}
	end.

create_channel(Connection) ->
	case amqp_connection:open_channel(Connection) of
		{ok, Channel} -> Channel;
		closing -> retry;
		_Err ->
			undefined
	end.

create_connection_for(Broker, State) ->
	case amqp_connection:start(Broker#broker.params) of
		{ok, Connection} ->
			NewBroker = Broker#broker{ connection = Connection },
			Brokers = dict:store(Broker#broker.name, NewBroker, State#state.brokers),
			{Connection, State#state{ brokers = Brokers } };
		_Err ->
			{undefined, State}
	end.

get_connection(Broker, State) ->
	Brokers = State#state.brokers,
	case dict:is_key(Broker, Brokers) of
		true ->
			B = dict:fetch(Broker, Brokers),
			get_connection_for(B, State);
		_Err ->
			{undefined, State}
	end.

get_channel_for(Key, State) ->
	[Broker | _ ] = dict:fetch_keys(State#state.brokers),
	get_channel_for(Broker, Key, State).

get_channel_for(Broker, Key, State) ->
	Channels = State#state.channels,
	case valid_channel(Key, Channels) of
		false -> add_channel(Broker, Key, State);
		true -> {dict:fetch(Key, Channels), State}
	end.

get_connection_for(Broker, State) ->
	Connection = Broker#broker.connection,
	case valid_connection(Connection) of
		true -> {Connection, State};
		_ ->
			create_connection_for(Broker, State)
	end.

valid_channel(Key, Channels) ->
	case dict:is_key(Key, Channels) of
		false -> 
			false;
		true ->
			case dict:fetch(Key, Channels) of
				Channel when is_pid(Channel) ->
					Alive = is_process_alive(Channel),
					Alive;
				_ -> 
					false
			end
	end.

valid_connection(Connection) ->
	case is_pid(Connection) of
		true -> 
			case is_process_alive(Connection) of
				true ->
					case amqp_connection:info(Connection, [is_closing]) of
						[{is_closing, true}] -> false;
						_ -> true
					end;
				_ -> false
			end;
		_ -> false
	end.