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

%% @author David Haglund
%% @copyright 2011, David Haglund
%% @doc
%%
%% @end

-module(epa_master_tests).

-include_lib("eunit/include/eunit.hrl").

-export([]).

start_stop_test() ->
    {ok, Pid} = epa_master:start_link([]),
    ?assertNot(undefined == process_info(Pid)),
    ?assertMatch(Pid when is_pid(Pid), whereis(epa_master)),
    Ref = monitor(process, Pid),
    ok = epa_master:stop(),
    receive {'DOWN', Ref, process, _, _} -> ok end,
    ?assert(undefined == process_info(Pid)),
    ?assertEqual(undefined, whereis(epa_master)).

read_simple_config_and_start_epc_test() ->
    mock(),

    WorkerCallback = epw_dummy,
    Config = [{topology, [{dummy, epw, WorkerCallback, 2, []}]}],

    {ok, _Pid} = epa_master:start_link(Config),

    ?assert(meck:called(epw_sup_master, start_worker_sup, [WorkerCallback])),
    ?assert(meck:called(epc_sup, start_epc, [self()])),
    teardown().

read_config_with_two_connected_epcs_test() ->
    mock(),
    SenderCallback = sender_callback,
    ReceiverCallback = receiver_callback,
    mock_epw_callback(SenderCallback),
    mock_epw_callback(ReceiverCallback),
    Config = [{topology, [{sender, epw, SenderCallback, 2, [{receiver, all}]},
                          {receiver, epw, ReceiverCallback, 2, []}
                         ]
              }],

    {ok, _Pid} = epa_master:start_link(Config),

    ?assert(meck:called(epw_sup_master, start_worker_sup, [SenderCallback])),
    ?assert(meck:called(epw_sup_master, start_worker_sup, [ReceiverCallback])),
    ?assertEqual(2, meck_improvements:count_calls(epc_sup, start_epc, [self()])),
    ?assert(meck:called(epc, set_targets, [self(), [{self(), all}]])),
    meck:unload(SenderCallback),
    meck:unload(ReceiverCallback),
    teardown().

%
% Config check tests
%
invalid_topology_syntax_check_test() ->
    InvalidTopology1 = [{topology, [foo]}],
    InvalidTopology2 = [{topology, [{foo, epw, bar, 1}]}],
    InvalidTopology3 = [{topology, [{foo, epw, bar, 1, [], []}]}],
    InvalidTopology4 = [{topology, [{1, epw, bar, 1, foo}]}],
    InvalidTopology5 = [{topology, [{foo, 2, bar, 1, foo}]}],
    InvalidTopology6 = [{topology, [{foo, epw, 3, 1, foo}]}],
    InvalidTopology7 = [{topology, [{foo, epw, bar, baz, []}]}],

    ?assertEqual({error, {invalid_topology_syntax, foo}},
                 epa_master:start_link(InvalidTopology1)),
    ?assertEqual({error, {invalid_topology_syntax, {foo, epw, bar, 1}}},
                 epa_master:start_link(InvalidTopology2)),
    ?assertEqual({error, {invalid_topology_syntax, {foo, epw, bar, 1, [], []}}},
                 epa_master:start_link(InvalidTopology3)),
    ?assertEqual({error, {invalid_topology_syntax, {1, epw, bar, 1, foo}}},
                 epa_master:start_link(InvalidTopology4)),
    ?assertEqual({error, {invalid_topology_syntax, {foo, 2, bar, 1, foo}}},
                 epa_master:start_link(InvalidTopology5)),
    ?assertEqual({error, {invalid_topology_syntax, {foo, epw, 3, 1, foo}}},
                 epa_master:start_link(InvalidTopology6)),
    ?assertEqual({error, {invalid_topology_syntax, {foo, epw, bar, baz, []}}},
                 epa_master:start_link(InvalidTopology7)).

invalid_topology_target_syntax_check_test() ->
    InvalidTopology1 = [{topology, [{foo, epw, bar, 1, foo}]}],
    InvalidTopology2 = [{topology, [{foo, epw, bar, 1, [foo]}]}],
    InvalidTopology3 = [{topology, [{foo, epw, bar, 1, [{foo}]}]}],
    InvalidTopology4 = [{topology, [{foo, epw, bar, 1, [{foo, bar, baz}]}]}],
    InvalidTopology5 = [{topology, [{foo, epw, bar, 1, [{4, bar}]}]}],
    InvalidTopology6 = [{topology, [{foo, epw, bar, 1, [{foo, 5}]}]}],

    ?assertEqual({error, {invalid_topology_syntax, {foo, epw, bar, 1, foo}}},
                 epa_master:start_link(InvalidTopology1)),
    ?assertEqual({error, {invalid_topology_target_syntax, foo}},
                 epa_master:start_link(InvalidTopology2)),
    ?assertEqual({error, {invalid_topology_target_syntax, {foo}}},
                 epa_master:start_link(InvalidTopology3)),
    ?assertEqual({error, {invalid_topology_target_syntax, {foo, bar, baz}}},
                 epa_master:start_link(InvalidTopology4)),
    ?assertEqual({error, {invalid_topology_target_syntax, {4, bar}}},
                 epa_master:start_link(InvalidTopology5)),
    ?assertEqual({error, {invalid_topology_target_syntax, {foo, 5}}},
                 epa_master:start_link(InvalidTopology6)).

invalid_topology_target_references_test() ->
    InvalidTargetRef1 = [{topology, [{name, epw, bar, 1, [{name, all}]}]}],
    InvalidTargetRef2 = [{topology, [{name, epw, bar, 1,
                                      [{invalid_name, all}]}]}],
    InvalidTargetRef3 = [{topology, [{name1, epw, bar, 1, []},
                                     {name2, epw, bar, 1,
                                      [{name1, all},
                                       {invalid_name, all}]}]}],
    ?assertEqual({error, {invalid_target_ref, name}},
                 epa_master:start_link(InvalidTargetRef1)),
    ?assertEqual({error, {invalid_target_ref, invalid_name}},
                 epa_master:start_link(InvalidTargetRef2)),
    ?assertEqual({error, {invalid_target_ref, invalid_name}},
                 epa_master:start_link(InvalidTargetRef3)),
    ok.

invalid_topology_terget_ref_type_test() ->
    InvalidTargetRefType = [{topology, [{name1, epw, bar, 1, []},
                                         {name2, epw, bar, 1,
                                          [{name1, foo}]}]}],
    ?assertEqual({error, {invalid_target_ref_type, foo}},
                 epa_master:start_link(InvalidTargetRefType)).

valid_topology_terget_ref_type_test() ->
    ValidTargetRefType1 = [{topology, [{name1, epw, epw_dummy, 1, []},
                                      {name2, epw, epw_dummy, 1,
                                       [{name1, all}]}]}],
    ValidTargetRefType2 = [{topology, [{name1, epw, epw_dummy, 1, []},
                                      {name2, epw, epw_dummy, 1,
                                       [{name1, random}]}]}],
    ValidTargetRefType3 = [{topology, [{name1, epw, epw_dummy, 1, []},
                                      {name2, epw, epw_dummy, 1,
                                       [{name1, keyhash}]}]}],
    mock(),
    ?assertMatch({ok, _Pid},
                 epa_master:start_link(ValidTargetRefType1)),
    epa_master:stop(),

    ?assertMatch({ok, _Pid},
                 epa_master:start_link(ValidTargetRefType2)),
    epa_master:stop(),

    ?assertMatch({ok, _Pid},
                 epa_master:start_link(ValidTargetRefType3)),

    teardown(),
    ok.

invalid_topology_duplicated_worker_name_test() ->
    DupName = [{topology, [{name, epw, bar, 1, []},
                           {name, epw, bar, 1, []}]}],
    ?assertEqual({error, duplicated_worker_name},
                 epa_master:start_link(DupName)).

invalid_topology_worker_type_test() ->
    InvalidWorkerType = [{topology, [{name, foo, bar, 1, []}]}],
    ?assertEqual({error, {invalid_worker_type, foo}},
                 epa_master:start_link(InvalidWorkerType)).

invalid_topology_worker_callback_module_test() ->
    InvalidWorkerCallbackModule = [{topology, [{name, epw, invalid_callback, 1, []}]}],
    ?assertEqual({error, {invalid_worker_callback_module, invalid_callback}},
                 epa_master:start_link(InvalidWorkerCallbackModule)).

%% Internal functions
mock() ->
    meck:new(epw_sup_master),
    meck:new(epc_sup),
    meck:new(epc),
    meck:expect(epw_sup_master, start_worker_sup, 1, {ok, self()}),
    meck:expect(epc_sup, start_epc, 1, {ok, self()}),
    meck:expect(epc, set_targets, 2, ok).

mock_epw_callback(CallbackModule) ->
    meck:new(CallbackModule),
    meck:expect(CallbackModule, init, fun(State) -> {ok, State} end),
    meck:expect(CallbackModule, process, fun(_Msg, _EmitFun, State) -> {ok, State} end),
    meck:expect(CallbackModule, terminate, fun(_Reason, State) -> State end).

teardown() ->
    unload_mocks(),
    epa_master:stop().

unload_mocks() ->
    meck:unload(epc),
    meck:unload(epc_sup),
    meck:unload(epw_sup_master).