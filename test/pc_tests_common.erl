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

-module(pc_tests_common).

-include_lib("eunit/include/eunit.hrl").

-compile(export_all).

test_behaviour_info(TestMod, Expected) ->
    Mod = mod(TestMod),
    Actual = Mod:behaviour_info(callbacks),
    ?assertEqual(Expected, Actual),
    ?assertEqual(undefined, Mod:behaviour_info(foo)).

test_start_stop(TestMod) ->
    Mock = TestMod:create_mock(),
    Mod = mod(TestMod),
    {ok, Pid} = Mod:start_link(Mock, [], []),
    ?assertNot(undefined == process_info(Pid)),
    ?assertMatch({ok, _}, Mod:stop(Pid)),
    delete_mock(Mock).

should_return_the_state_in_stop(TestMod) ->
    [Mod, Pid, Mock, StateRef] = setup(TestMod),
    ?assertEqual({ok, StateRef}, Mod:stop(Pid)),
    delete_mock(Mock).

should_call_terminate_on_stop(TestMod) ->
    [Mod, Pid, Mock, StateRef] = setup(TestMod),
    Mod:stop(Pid),
    ?assert(meck:called(Mock, terminate, [normal, StateRef])),
    delete_mock(Mock).

validate_module(TestMod) ->
    Mock = TestMod:create_mock(),
    Mod = mod(TestMod),
    NotValidModule = not_valid_module,
    NotLoadedModule = not_loaded_module,
    meck:new(NotValidModule),
    ?assertNot(Mod:validate_module(NotValidModule)),
    ?assertNot(Mod:validate_module(NotLoadedModule)),
    ?assert(Mod:validate_module(Mock)),
    delete_mock(Mock),
    delete_mock(NotValidModule).

mocked_tests(TestMod) ->
    {foreach, fun() -> setup(TestMod) end, fun teardown/1,
     [{with, [T]} ||
      T <- common_mocked_tests() ++ special_mocked_tests(TestMod)
     ]}.

common_mocked_tests() ->
    [fun ?MODULE:should_call_init_/1,
     fun ?MODULE:should_handle_sync_/1,
     fun ?MODULE:should_not_crash_on_random_data_to_gen_server_callbacks_/1
    ].

special_mocked_tests(breeze_processing_worker_tests) ->
    [fun ?MODULE:should_call_process_/1];
special_mocked_tests(breeze_generating_worker_tests) ->
    [fun ?MODULE:should_not_call_generate_without_targets_/1].

should_call_init_([_Mod, _Pid, Mock, StateRef]) ->
    ?assert(meck:called(Mock, init, [StateRef])).

should_handle_sync_([Mod, Pid | _]) ->
    ?assertEqual(ok, Mod:sync(Pid)).

% breeze_processing_worker_tests only
should_call_process_([Mod, Pid, Mock, StateRef]) ->
    MessageRef = make_ref(),
    ok = Mod:process(Pid, MessageRef),
    Mod:sync(Pid), % Sync with the process to make sure it has processed
    ?assertEqual(1, meck:num_calls(Mock, process, [MessageRef, '_', StateRef])).

% breeze_generating_worker_tests only
should_not_call_generate_without_targets_([_Mod, _Pid, Mock | _]) ->
    ?assertEqual(0, meck:num_calls(Mock, generate, ['_', '_'])).

should_not_crash_on_random_data_to_gen_server_callbacks_([_Mod, Pid|_]) ->
    RandomData = {make_ref(), now(), foo, [self()]},
    gen_server:cast(Pid, RandomData),
    Pid ! RandomData,
    gen_server:call(Pid, RandomData).

verify_emitted_message_is_sent_to_all_targets(
  TestMod, EmitTriggerMock, EmitTriggerFun, Msg, EpcEmitFunc, DistKey) ->
    Mod = mod(TestMod),
    Mock = TestMod:create_mock(),
    EmitTriggerMock(Mock), % Mock the behaviour to execute the EmitFun
    meck:new(breeze_worker_controller),
    meck:expect(breeze_worker_controller, EpcEmitFunc, 2, ok),
    AnotherPid = create_pid(),
    Targets = [{self(), DistKey}, {AnotherPid, DistKey}],
    {ok, Pid} = Mod:start_link(Mock, [], [{targets, Targets}]),
    EmitTriggerFun(Pid),
    Mod:sync(Pid),
    ?assert(meck:validate(breeze_worker_controller)),
    ?assert(meck:called(breeze_worker_controller, EpcEmitFunc, [self(), Msg])),
    ?assert(meck:called(breeze_worker_controller, EpcEmitFunc,
			[AnotherPid, Msg])),
    Mod:stop(Pid),
    delete_mock(Mock),
    meck:unload(breeze_worker_controller).

%%%===================================================================
%%% utility functions
%%%===================================================================
delete_mock(Mock) ->
    meck:unload(Mock).

create_pid() ->
     spawn(fun() -> timer:sleep(infinity) end).

%%%===================================================================
%%% Internal functions
%%%===================================================================
setup(TestMod) ->
    Mod = mod(TestMod),
    Mock = TestMod:create_mock(),
    StateRef = make_ref(),
    {ok, Pid} = Mod:start_link(Mock, StateRef, []),
    [Mod, Pid, Mock, StateRef].

teardown([Mod, Pid, Mock | _]) ->
    Mod:stop(Pid),
    delete_mock(Mock).

mod(TestMod) ->
    TestMod:tested_module().
