%%% @author Alex Robson
%%% @copyright 2014
%%% @doc
%%%		I'm sure it's awful, but it's one step above registering every
%%%		process by a generated atom and I won't gproc.
%%% @end
%%% @license MIT
%%% Created January 26, 2014 by Alex Robson

-module(vrpl_process).

-export([get/1, init/0, store/1]).

-define(TABLE, vrpl_processes).

init() ->
	case ets:info(?TABLE) of
		undefined ->
			ets:new(?TABLE, [ordered_set, public, named_table, {read_concurrency, true}, {write_concurrency, true}]);
		_ -> ok
	end.

get(Id) ->
	Match = case ets:lookup(?TABLE, Id) of
		[] -> undefined;
		[{_,Pid}] -> Pid
	end,
	Live = is_pid(Match) andalso is_process_alive(Match),
	if
		Live -> Match;
		true -> undefined
	end.

store(Id) -> ets:insert(?TABLE, {Id, self()}).