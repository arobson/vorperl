%%% @author Alex Robson
%%% @copyright 2014
%%% @doc
%%%		Expose channel creation and manage connections to brokers
%%%		transparently.
%%% @end
%%% @license MIT
%%% Created January 26, 2014 by Alex Robson

-module(vrpl_connection).

-behavior(gen_server).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([
	create_channel/0,
	create_channel/1
	]).

-record(state, {}).

-define(DEFAULT, "default").
-define(TABLE, vrpl_connections).
-define(SERVER, ?MODULE).

%% ===================================================================
%%  API
%% ===================================================================

create_channel() -> new_channel(?DEFAULT).
create_channel(ConnectionName) -> call({channel, ConnectionName}).

call(Message) -> gen_server:call(?SERVER, Message).

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

handle_call({channel, ConnectionName}, _From, State) ->
	{reply, new_channel(ConnectionName), State};
 
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

%% ===================================================================
%%  Internal
%% ===================================================================

new_channel(Name) ->
	case get_connection(Name) of
		{connection_failed, Err} -> {connection_failed, Err};
		Connection ->
			case amqp_connection:open_channel(Connection) of
				{ok, Channel} -> 
					amqp_channel:register_return_handler(Channel, self()),
					Channel;
				closing -> retry;
				{error, Err2} -> {connection_failed, Err2}
			end
	end.

create_connection(Name) ->
	Params = vrpl_configuration:get_broker(Name),
	Broker = amqp_util:broker_declare(Params),
	case amqp_connection:start(Broker) of
		{ok, Connection} ->
			store(Name, Connection),
			Connection;
		{error, Err} -> {connection_failed, Err}
	end.

get_connection(Name) ->
	Connection = lookup(Name),
	case valid_connection(Connection) of
		true -> Connection;
		_ -> create_connection(Name)
	end.

valid_connection(undefined) -> false;
valid_connection(Connection) ->
	IsValid = is_pid(Connection) andalso is_process_alive(Connection),
	if 
		IsValid ->
			case amqp_connection:info(Connection, [is_closing]) of
				[{is_closing, true}] -> false;
				_ -> true
			end;
		true -> false
	end.

%% ===================================================================
%%  ETS
%%  Wrappers for interactions with ETS. Connections should be
%%  durable and long-lived. This is, perhaps, not the best use of the 
%%  error kernel pattern, but it's an improvement over what I had 
%%  previously. Mostly, it's to keep problems in other areas of my
%%  design from losing track of connections and creating loads of them.
%% ===================================================================

init_ets() ->
	case ets:info(?TABLE) of
		undefined ->
			ets:new(?TABLE, [ordered_set, public, named_table, {read_concurrency, true}]);
		_ -> ok
	end.

lookup(Name) ->
	case ets:lookup(?TABLE, {connection, Name}) of
		[] -> undefined;
		[{_, Connection}] -> Connection
	end.

store(Name, Connection) -> ets:insert(?TABLE, {{connection, Name}, Connection}).