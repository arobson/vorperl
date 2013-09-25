%%% @author Alex Robson
%%% @copyright 2013
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created September 24, 2013 by Alex Robson

-module(test).
-compile([export_all]).
-include_lib("eunit/include/eunit.hrl").



get_json_representation() ->
	<<"{\"container\":1,\"list\":[{\"id\":1,\"content\":\"hello\"},{\"id\":2,\"content\":\"world\"}]}">>.

get_object_representation() ->
	[{container,1},{list,[[{id,1},{content,"hello"}],[{id,2},{content,"world"}]]}].

json_to_props_test() ->
	Json = get_json_representation(),
	Term = get_object_representation(),
	?assertEqual(
		message_util:json_decode(Json),
		Term).

props_to_json_test() ->
	Json = get_json_representation(),
	Term = get_object_representation(),
	?assertEqual(
		message_util:json_encode(Term),
		Json).