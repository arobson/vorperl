%%% @author Alex Robson
%%% @copyright 2014
%%% @doc
%%% 	Manage created channels in an ETS table to allow concurrent access
%%% 	and prevent various processes who need to access their channel
%%% 	from stacking up behind one another.
%%% 	In the event the channel hasn't been created yet, use the gen_server
%%% 	to serialize creation and prevent race conditions or concurrent
%%% 	writes to the ETS table.
%%% @end
%%% @license MIT
%%% Created January 26, 2014 by Alex Robson

-module(vrpl_channel).

-behavior(gen_server).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([
	get/1,
	get/2
	]).

-record(state, {}).

-define(DEFAULT, "default").
-define(TABLE, vrpl_channels).
-define(SERVER, ?MODULE).

%% ===================================================================
%%  API
%% ===================================================================

get(Name) -> get_channel(Name, ?DEFAULT).
get(Name, ConnectionName) -> get_channel(Name, ConnectionName).

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

handle_call({new_channel, Name, ConnectionName}, _From, State) ->
	{reply, new_channel(Name, ConnectionName), State};
 
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

call(Message) -> gen_server:call(?SERVER, Message).

%% If there's not a valid channel available,
%% this uses the gen server to serialize calls to
%% create to prevent conflicting writes/races
get_channel(Name, ConnectionName) ->
	Channel = lookup(Name),
	case valid_channel(Channel) of
		false -> call({new_channel, Name, ConnectionName});
		Channel -> Channel
	end.

%% Make one last call to lookup to see if a missing channel
%% was created just before
new_channel(Name, ConnectionName) ->
	case lookup(Name) of
		undefined ->
			Channel = vrpl_connection:create_channel(ConnectionName),
			store(Name, Channel),
			Channel;
		Channel -> Channel
	end.

valid_channel(Channel) when is_pid(Channel) ->
	is_process_alive(Channel);
valid_channel(_) -> false.

%% ===================================================================
%%  ETS
%%  Wrappers for interactions with ETS. Channels should be
%%  relatively slow-changing and need proper disposal. Entrusting them
%%  to the exchange or queue process that will be using them seems
%%  dangerous. This is, perhaps, not the best use of the error kernel
%%  pattern, but it's an improvement over what I had previously.
%% ===================================================================

init_ets() ->
	case ets:info(?TABLE) of
		undefined ->
			ets:new(?TABLE, [ordered_set, public, named_table, {read_concurrency, true}]);
		_ -> ok
	end.

lookup(Name) ->
	case ets:lookup(?TABLE, {channel, Name}) of
		[] -> undefined;
		[{_, Channel}] -> Channel
	end.

store(Name, Channel) -> ets:insert(?TABLE, {{channel, Name}, Channel}).