%%% @author Alex Robson
%%% @copyright 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 25, 2012 by Alex Robson

-module(message_util).

-export([ 
			bert_encode/1,
			bert_decode/1,
			default_providers/0,
			encode_message/3,
			json_encode/1,
			json_decode/1
		]).

bert_encode(Term) ->
	term_to_binary(Term).

bert_decode(Binary) ->
	binary_to_term(Binary).

json_encode(PropList) ->
	json:encode(PropList).

json_decode(Json) ->
	json:decode(Json).

default_providers() ->
	Json_Coders = { 
		fun(X) -> json_encode(X) end,
		fun(X) -> json_decode(X) end 
	},
	Bert_Coders = {
		fun(X) -> bert_encode(X) end,
		fun(X) -> bert_decode(X) end 			
	},
	dict:from_list([
		{<<"application/json">>, Json_Coders },
		{<<"application/x-erlang-binary">>, Bert_Coders }
	]).

encode_message(Msg, Flags, Providers) ->
	ContentType = proplists:get_value(content_type, Flags, <<"text/plain">>),
	case dict:is_key(ContentType, Providers) of
		true -> 
			{Encoder, _} = dict:fetch( ContentType, Providers ),
			Encoder(Msg);
		_ -> amqp_util:to_bin(Msg)
	end.