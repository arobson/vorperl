-module(vrpl_demo).

-export([go/0]).

go() ->
	vorperl:broker(),
	vorperl:exchange("x1",[auto_delete, {content_type, "application/x-erlang-binary"}]),
	vorperl:queue("q1",[auto_delete]),
	vorperl:bind("x1","q1",""),
	vorperl:start_subscription("q1"),
	[ vorperl:publish("x1", [{message,"test"},{id,X}]) || X <- lists:seq(1, 50000) ].