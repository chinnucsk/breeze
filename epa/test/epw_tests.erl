%%====================================================================
%% Copyright (c) 2011, David Haglund
%% All rights reserved.
%%
%% Redistribution and use in source and binary forms, with or without
%% modification, are permitted provided that the following conditions
%% are met:
%%
%%     * Redistributions of source code must retain the above
%%       copyright notice, this list of conditions and the following
%%       disclaimer.
%%
%%     * Redistributions in binary form must reproduce the above
%%       copyright notice, this list of conditions and the following
%%       disclaimer in the documentation and/or other materials
%%       provided with the distribution.
%%
%%     * Neither the name of the copyright holder nor the names of its
%%       contributors may be used to endorse or promote products
%%       derived from this software without specific prior written
%%       permission.
%%
%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
%% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
%% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
%% FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
%% COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
%% INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
%% (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
%% SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
%% HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
%% STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
%% ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
%% OF THE POSSIBILITY OF SUCH DAMAGE.
%%====================================================================
-module(epw_tests).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

-behaviour(epw).
-export([init/1, process/2, terminate/2]).

% callback methods
init(Pid) when is_pid(Pid) ->
    Pid ! init,
    {ok, []};
init(Args) ->
    {ok, Args}.

process(Pid, State) when is_pid(Pid) ->
    Pid ! {process, State},
    {ok, State};
process(_Data, State) ->
    {ok, State}.

terminate(_Reason, List) when is_list(List) ->
    case proplists:get_value(terminate, List) of
        Pid when is_pid(Pid) ->
            Pid ! {stopped, List},
            terminated;
        undefined ->
            not_the_state
    end;
terminate(_Reason, State) ->
    State.

% Tests
start_stop_test() ->
    {ok, Pid} = epw:start_link(?MODULE, []),
    ?assertNot(undefined == process_info(Pid)),
    {ok, _} = epw:stop(Pid).

% TODO: rewrite without receive
init_test() ->
    Pid = start(),
    receive init -> ok end,
    epw:stop(Pid).

stop_should_return_the_state_test() ->
    Ref = make_ref(),
    Pid = start(Ref),
    ?assertEqual({ok, Ref}, epw:stop(Pid)).

% TODO: rewrite without receive
stop_should_call_terminate_test() ->
    Args = [{terminate, self()}],
    Pid = start(Args),
    ?assertEqual({ok, terminated}, epw:stop(Pid)),
    receive {stopped, Args} -> ok end.

behaviour_info_test() ->
    Expected = [{init,1},
                {process, 2},
                {terminate,2}],
    Actual = epw:behaviour_info(callbacks),
    ?assertEqual(Expected, Actual),
    ?assertEqual(undefined, epw:behaviour_info(foo)).

validate_module_test() ->
    ?assertNot(epw:validate_module(not_valid_module)),
    ?assert(epw:validate_module(?MODULE)).

sync_test() ->
    meck:new(epw, [passthrough]),
    Pid = start(),
    ok = epw:sync(Pid),
    ?assertEqual(1, meck_improvements:count_calls_wildcard(
                   epw, handle_call, [sync | '_'])),
    epw:stop(Pid),
    catch meck:unload(epw).

% TODO: rewrite without receive
process_test() ->
    Ref = make_ref(),
    Pid = start(Ref),
    epw:process(Pid, self()),
    receive {process, Ref} -> ok end,
    epw:stop(Pid).

% Helper functions
flush() ->
    receive _Any -> flush()
    after 0 -> true
    end.

start() ->
    start(self()).

start(UserArgs) ->
    flush(),
    {ok, Pid} = epw:start_link(?MODULE, UserArgs),
    Pid.

-endif.
