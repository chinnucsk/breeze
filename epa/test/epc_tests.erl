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

-module(epc_tests).

-include_lib("eunit/include/eunit.hrl").

-compile(export_all).

-define(EPC_NAME, epc_name).

tests_with_mock_test_() ->
    {foreach, fun ?MODULE:setup/0, fun teardown/1,
     [{with, [T]} ||
      T <- [fun ?MODULE:t_start_stop/1,
            fun ?MODULE:t_register_name/1,
            fun ?MODULE:t_start_workers/1,
            fun ?MODULE:t_start_workers_with_same_config/1,
            fun ?MODULE:t_should_not_allow_start_workers_once/1,
            fun ?MODULE:t_restart_worker_when_it_crash/1,
            fun ?MODULE:t_restarted_worker_should_keep_its_place/1,
            fun ?MODULE:t_pass_worker_config_to_worker_on_restart/1,
            fun ?MODULE:t_multicast/1,
            fun ?MODULE:t_sync/1,
            fun ?MODULE:t_random_cast/1,
            fun ?MODULE:t_keyhash_cast/1,
            fun ?MODULE:t_keyhash_cast_error/1,
            fun ?MODULE:t_enable_dynamic_workers/1,
            fun ?MODULE:t_cant_activate_dynamic_workers_with_workers_started/1,
            fun ?MODULE:t_cant_start_workers_after_enabled_dynamic_workers/1,
            fun ?MODULE:t_start_dynamic_worker_when_doing_first_keycast/1,
            fun ?MODULE:t_start_dynamic_worker_should_set_targets/1,
            fun ?MODULE:t_send_message_to_started_worker_when_doing_first_keycast/1,
            fun ?MODULE:t_same_key_as_already_started_should_not_start_new_worker/1,
            fun ?MODULE:t_remember_the_old_dynamic_workers_when_starting_new_ones/1,
            fun ?MODULE:t_dynamic_workers_should_be_restarted_if_they_crash/1,
            fun ?MODULE:t_dynamic_cast_messages_must_be_a_tuple_with_a_key/1,
            fun ?MODULE:t_dynamic_should_not_only_handle_dynamic_cast/1,
            fun ?MODULE:t_non_dynamic_should_not_handle_unique/1,
            fun ?MODULE:t_config_with_one_epc_target/1,
            fun ?MODULE:t_should_not_crash_on_random_data/1,
            fun ?MODULE:t_should_do_nothing_on_cast_with_no_workers/1
           ]]}.

t_start_stop([Pid | _]) ->
    ?assertNot(undefined == process_info(Pid)).

t_register_name([Pid | _]) ->
    ?assertEqual(Pid, whereis(?EPC_NAME)).

t_start_workers([Pid, WorkerSup | _]) ->
    ?assertEqual(ok, epc:start_workers(Pid, 2)),
    ?assertMatch([_, _], supervisor:which_children(WorkerSup)).

t_start_workers_with_same_config([Pid, _WorkerSup, WorkerMod, MockModule|_]) ->
    WorkerConfig = [make_ref()],
    ?assertEqual(ok, epc:start_workers(Pid, 1, WorkerConfig)),
    ?assert(meck:called(WorkerMod, start_link,
                        [MockModule, WorkerConfig, []])).

t_pass_worker_config_to_worker_on_restart(
  [Pid, WorkerSup, WorkerMod, MockModule|_]) ->
    WorkerConfig = [make_ref()],
    ok = epc:start_workers(Pid, 1, WorkerConfig),
    [Worker] = get_workers(WorkerSup),
    sync_exit(Worker),
    ?assertEqual(0, meck:num_calls(WorkerMod, start_link,
                                   [MockModule, [], []])),
    ?assertEqual(2, meck:num_calls(WorkerMod, start_link,
                                   [MockModule, WorkerConfig, []])).

t_should_not_allow_start_workers_once([Pid, WorkerSup | _ ]) ->
    ok = epc:start_workers(Pid, 1),
    ?assertEqual({error, already_started}, epc:start_workers(Pid, 1)),
    ?assertMatch([_], get_workers(WorkerSup)).

t_restart_worker_when_it_crash([Pid, WorkerSup | _]) ->
    ok = epc:start_workers(Pid, 1),
    [Worker] = get_workers(WorkerSup),
    sync_exit(Worker),
    ?assertMatch([_], get_workers(WorkerSup)).

t_restarted_worker_should_keep_its_place([Pid, WorkerSup | _]) ->
    ok = epc:start_workers(Pid, 2),
    Workers = get_workers(WorkerSup),
    Msg1 = {foo, 1},
    Msg2 = {bar, 2},
    ok = epc:keyhash_cast(Pid, Msg1),
    ok = epc:sync(Pid),
    [FirstWorker | _ ] = OrderedWorkers = order_workers(Workers, Msg1),
    assert_workers_process_function_is_called(OrderedWorkers, [1, 0], Msg1),
    sync_exit(FirstWorker),
    Workers2 = get_workers(WorkerSup),
    [NewWorker] = Workers2 -- Workers,
    OrderedWorkers2 = replace(OrderedWorkers, FirstWorker, NewWorker),
    keyhash_cast_and_assert(Pid, Msg1, OrderedWorkers2, [1, 0]),
    keyhash_cast_and_assert(Pid, Msg2, OrderedWorkers2, [0, 1]),
    ok.

t_multicast([Pid, WorkerSup, WorkerMod| _]) ->
    Msg = msg,
    ok = epc:start_workers(Pid, 2),
    epc:multicast(Pid, Msg),
    epc:sync(Pid),
    assert_workers_are_called(WorkerMod, WorkerSup, process, [Msg]),
    ok.

t_sync([Pid, WorkerSup, WorkerMod | _]) ->
    ok = epc:start_workers(Pid, 2),
    ?assertEqual(ok, epc:sync(Pid)),
    assert_workers_are_called(WorkerMod, WorkerSup, sync),
    ok.

t_random_cast([Pid, WorkerSup | _]) ->
    meck:new(random, [passthrough, unstick]),
    ok = epc:start_workers(Pid, 2),
    meck:sequence(random, uniform, 1, [1, 1, 2]),
    Workers = get_workers(WorkerSup),
    ok = epc:random_cast(Pid, Msg = msg),
    ok = epc:sync(Pid),

    OrderedWorkers = order_workers(Workers, Msg),
    assert_workers_random_and_process(OrderedWorkers, [1, 0], Msg),
    random_cast_and_assert(Pid, Msg, OrderedWorkers, [2, 0]),
    random_cast_and_assert(Pid, Msg, OrderedWorkers, [2, 1]),
    meck:unload(random).

t_keyhash_cast([Pid, WorkerSup | _]) ->
    ok = epc:start_workers(Pid, 2),
    Workers = get_workers(WorkerSup),
    Msg1 = {foo, 1},
    Msg2 = {bar, 2},
    ok = epc:keyhash_cast(Pid, Msg1),
    ok = epc:sync(Pid),
    OrderedWorkers = order_workers(Workers, Msg1),
    assert_workers_process_function_is_called(OrderedWorkers, [1, 0], Msg1),

    keyhash_cast_and_assert(Pid, Msg1, OrderedWorkers, [2, 0]),
    keyhash_cast_and_assert(Pid, Msg2, OrderedWorkers, [0, 1]),
    ok.

t_keyhash_cast_error([Pid | _]) ->
    Msg1 = foo,
    Msg2 = {},
    ?assertEqual({error, {not_a_valid_message, Msg1}},
                 epc:keyhash_cast(Pid, Msg1)),
    ?assertEqual({error, {not_a_valid_message, Msg2}},
                 epc:keyhash_cast(Pid, Msg2)).

t_enable_dynamic_workers([Pid, _WorkerSup | _]) ->
    ?assertEqual(ok, epc:enable_dynamic_workers(Pid)),
    ?assertEqual(ok, epc:enable_dynamic_workers(Pid)).

t_cant_activate_dynamic_workers_with_workers_started([Pid | _]) ->
    ok = epc:start_workers(Pid, 1),
    ?assertEqual({error, workers_already_started}, epc:enable_dynamic_workers(Pid)).

t_cant_start_workers_after_enabled_dynamic_workers([Pid | _ ]) ->
    ok = epc:enable_dynamic_workers(Pid),
    ?assertEqual({error, dynamic_workers}, epc:start_workers(Pid, 1)).

t_start_dynamic_worker_when_doing_first_keycast([Pid, WorkerSup | _]) ->
    ok = epc:enable_dynamic_workers(Pid),
    epc:dynamic_cast(Pid, {key1, data1}),
    epc:sync(Pid),
    ?assertEqual(1, length(get_workers(WorkerSup))).

t_start_dynamic_worker_should_set_targets(
  [Pid, _WorkerSup, WorkerMod, MockModule | _]) ->
    {OtherEpc, _WorkerSup2} = start(another_epc, WorkerMod, MockModule),
    Targets = [{OtherEpc, all}],
    ok = epc:set_targets(Pid, Targets),
    ok = epc:enable_dynamic_workers(Pid),
    epc:dynamic_cast(Pid, {key1, data1}),
    epc:sync(Pid),
    ?assertEqual(1, meck:num_calls(WorkerMod, start_link,
                                   [MockModule, [], [{targets, Targets}]])),
    epc:stop(OtherEpc).

t_send_message_to_started_worker_when_doing_first_keycast(
  [Pid, WorkerSup, WorkerMod | _]) ->
    ok = epc:enable_dynamic_workers(Pid),
    Msg = {key1, data1},
    epc:dynamic_cast(Pid, Msg),
    epc:sync(Pid),
    [WorkerPid] = get_workers(WorkerSup),
    ?assertEqual(1, meck:num_calls(WorkerMod, process, [WorkerPid, Msg])).

t_same_key_as_already_started_should_not_start_new_worker(
  [Pid, WorkerSup, WorkerMod | _]) ->
    ok = epc:enable_dynamic_workers(Pid),
    Msg1 = {key1, data1},
    Msg2 = {key1, data2},
    epc:dynamic_cast(Pid, Msg1),
    epc:dynamic_cast(Pid, Msg1),
    epc:dynamic_cast(Pid, Msg2),
    epc:sync(Pid),
    ?assertMatch([_], get_workers(WorkerSup)),
    [WorkerPid] = get_workers(WorkerSup),
    ?assertEqual(2, meck:num_calls(WorkerMod, process, [WorkerPid, Msg1])),
    ?assertEqual(1, meck:num_calls(WorkerMod, process, [WorkerPid, Msg2])).

t_remember_the_old_dynamic_workers_when_starting_new_ones(
  [Pid, WorkerSup, WorkerMod | _]) ->
    ok = epc:enable_dynamic_workers(Pid),
    Msg1 = {key1, data1},
    Msg2 = {key2, data2},
    epc:dynamic_cast(Pid, Msg1),
    epc:dynamic_cast(Pid, Msg2),
    epc:dynamic_cast(Pid, Msg1),
    epc:sync(Pid),
    ?assertEqual(2, meck:num_calls(WorkerMod, start_link, '_')),
    [WorkerPid1, WorkerPid2] = get_workers(WorkerSup),
    ?assertEqual(2, meck:num_calls(WorkerMod, process, [WorkerPid1, Msg1])),
    ?assertEqual(1, meck:num_calls(WorkerMod, process, [WorkerPid2, Msg2])).

t_dynamic_workers_should_be_restarted_if_they_crash(
  [Pid, WorkerSup, WorkerMod | _ ]) ->
    ok = epc:enable_dynamic_workers(Pid),
    Msg1 = {key1, data1},
    Msg2 = {key2, data2},
    epc:dynamic_cast(Pid, Msg1),
    epc:dynamic_cast(Pid, Msg2),
    epc:sync(Pid),
    Workers = [WorkerPid1, WorkerPid2] = get_workers(WorkerSup),
    sync_exit(WorkerPid1),
    ?assertEqual(3, meck:num_calls(WorkerMod, start_link, '_')),

    ?assertEqual(2, length(get_workers(WorkerSup))),
    Workers2 = get_workers(WorkerSup),
    [NewWorker] = Workers2 -- Workers,
    epc:dynamic_cast(Pid, Msg1),
    epc:sync(Pid),

    ?assertEqual(1, meck:num_calls(WorkerMod, process, [NewWorker, Msg1])),
    ?assertEqual(1, meck:num_calls(WorkerMod, process, [WorkerPid2, Msg2])),

    epc:dynamic_cast(Pid, Msg2),
    epc:sync(Pid),
    ?assertEqual(1, meck:num_calls(WorkerMod, process, [NewWorker, Msg1])),
    ?assertEqual(2, meck:num_calls(WorkerMod, process, [WorkerPid2, Msg2])).

t_dynamic_cast_messages_must_be_a_tuple_with_a_key([Pid | _]) ->
    ok = epc:enable_dynamic_workers(Pid),
    Msg1 = foo,
    Msg2 = {},
    ?assertEqual({error, {not_a_valid_message, Msg1}}, epc:dynamic_cast(Pid, Msg1)),
    ?assertEqual({error, {not_a_valid_message, Msg2}}, epc:dynamic_cast(Pid, Msg2)).

t_dynamic_should_not_only_handle_dynamic_cast([Pid, _WorkerSup, WorkerMod | _]) ->
    ok = epc:enable_dynamic_workers(Pid),
    Msg = {key1, data1},
    epc:dynamic_cast(Pid, Msg), % Create a worker
    epc:keyhash_cast(Pid, Msg),
    epc:multicast(Pid, Msg),
    epc:random_cast(Pid, Msg),
    epc:sync(Pid),
    ?assertEqual(1, meck:num_calls(WorkerMod, process, '_')).

t_non_dynamic_should_not_handle_unique([Pid, WorkerSup, WorkerMod | _ ]) ->
    epc:dynamic_cast(Pid, {key1, data1}),
    ?assertMatch([], get_workers(WorkerSup)),
    ?assertEqual(0, meck:num_calls(WorkerMod, process, '_')).


% TODO: should set callbackArgs in dynamically started workers

t_config_with_one_epc_target([Pid1, _WorkerSup1, WorkerMod, MockModule | _]) ->
    {OtherEpc, _WorkerSup2} = start(another_epc, WorkerMod, MockModule),
    Targets = [{OtherEpc, all}],
    ok = epc:set_targets(Pid1, Targets),
    ok = epc:start_workers(Pid1, 1),
    ?assert(meck:validate(WorkerMod)),
    ?assertEqual(1, meck:num_calls(WorkerMod, start_link,
                                   [MockModule, [], [{targets, Targets}]])),
    epc:stop(OtherEpc).

t_should_not_crash_on_random_data([Pid |_]) ->
    RandomData = {make_ref(), now(), foo, [self()]},
    Pid ! RandomData,
    gen_server:cast(Pid, RandomData),
    ?assertEqual({error, {invalid_request, RandomData}},
                 gen_server:call(Pid, RandomData)).

t_should_do_nothing_on_cast_with_no_workers([Pid | _]) ->
    Msg = {foo, 1},
    ?assertEqual(ok, epc:multicast(Pid, Msg)),
    ?assertEqual(ok, epc:random_cast(Pid, Msg)),
    ?assertEqual(ok, epc:keyhash_cast(Pid, Msg)),
    ?assertEqual(ok, epc:sync(Pid)).

should_seed_at_startup_test() ->
    meck:new(random, [passthrough, unstick]),
    S = setup(),
    ?assertEqual(1, meck:num_calls(random, seed, ['_', '_', '_'])),
    teardown(S),
    meck:unload(random).

% Assert functions
assert_workers_are_called(WorkerMod, WorkerSup, Func) ->
    assert_workers_are_called(WorkerMod, WorkerSup, Func, []).
assert_workers_are_called(WorkerMod, WorkerSup, Func, ExtraArgs) ->
    lists:foreach(fun(Pid) ->
                          ?assert(meck:called(WorkerMod, Func, [Pid] ++ ExtraArgs))
                  end, get_workers(WorkerSup)).

random_cast_and_assert(Pid, Msg, OrderedWorkers, ExpectedList) ->
    ok = epc:random_cast(Pid, Msg),
    ok = epc:sync(Pid),
    assert_workers_random_and_process(OrderedWorkers, ExpectedList, Msg).

keyhash_cast_and_assert(Pid, Msg, OrderedWorkers, ExpectedList) ->
    ok = epc:keyhash_cast(Pid, Msg),
    ok = epc:sync(Pid),
    assert_workers_process_function_is_called(OrderedWorkers, ExpectedList, Msg).


assert_workers_process_function_is_called(Workers, ExpectedList, Msg) ->
    lists:foreach(
      fun({Worker, Expected}) ->
              ?assertEqual(Expected, meck:num_calls(epw, process, [Worker, Msg]))
      end, lists:zip(Workers, ExpectedList)).

assert_workers_random_and_process(Workers, ExpectedList, Msg) ->
    NumberOfWorkers = length(Workers),
    ExpectedRandomUniformCalls = lists:sum(ExpectedList),
    ?assertEqual(ExpectedRandomUniformCalls, meck:num_calls(
                   random, uniform, [NumberOfWorkers])),
    assert_workers_process_function_is_called(Workers, ExpectedList, Msg).

% Setup/teardown functions
% TODO: make WorkerMod into a parameter
setup() ->
    WorkerMod = epw,
    meck:new(epw, [passthrough]),
    MockModule = create_behaviour_stub(WorkerMod),
    {Pid, WorkerSup} = start(?EPC_NAME, WorkerMod, MockModule),
    [Pid, WorkerSup, WorkerMod, MockModule].

create_behaviour_stub(epw) ->
    MockModule = epw_mock,
    ok = meck:new(MockModule),
    meck:expect(MockModule, init, fun(_) -> {ok, []} end),
    meck:expect(MockModule, process,
                fun(_Msg, _EmitFun, State) ->
                        {ok, State}
                end),
    meck:expect(MockModule, terminate, fun(_, State) -> State end),
    MockModule.

start(Name, WorkerMod, WorkerCallback) ->
    {ok, WorkerSup} = pc_sup:start_link(WorkerMod, WorkerCallback),
    {ok, Pid} = epc:start_link(Name, WorkerMod, WorkerSup),
    {Pid, WorkerSup}.

teardown([Pid, WorkerSup, WorkerMod, MockModule]) ->
    epc:stop(Pid),
    pc_sup:stop(WorkerSup),
    ok = meck:unload(MockModule),
    ok = meck:unload(WorkerMod).

% Getters
get_workers(WorkerSup) ->
    Children = supervisor:which_children(WorkerSup),
    lists:map(fun(Child) -> element(2, Child) end, Children).


% Other help methods

% Put the worker that receive the first process call first in the list
order_workers(Workers, Msg) ->
    case meck:num_calls(epw, process, [hd(Workers), Msg]) of
        1 ->
            Workers;
        _ -> % Reverse the order
            lists:reverse(Workers)
    end.

replace([Old | Rest], Old, New) ->
    [New | Rest];
replace([Other | Rest], Old, New) ->
    [Other | replace(Rest, Old, New)];
replace([], _Old, _New) ->
    [].

sync_exit(Pid) ->
    Ref = monitor(process, Pid),
    exit(Pid, crash),
    receive {'DOWN', Ref, process, _, _} -> ok end,
    timer:sleep(50). %% TODO: Find a way to get rid of this sleep.

