%%% @author Alex Robson
%%% @copyright Alex Robson, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 25, 2012 by Alex Robson

-module(message_util).

-export([ 
			bert_encode/1,
			bert_decode/1,
			json_encode/1,
			json_decode/1
		]).

bert_encode(Term) ->
	term_to_binary(Term).

bert_decode(Binary) ->
	binary_to_term(Binary).

json_encode(PropList) ->
	jiffy:encode({PropList}).

json_decode(Json) ->
	{PropList} = jiffy:decode(Json),
	PropList.