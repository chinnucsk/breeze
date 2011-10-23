NEW
---
* To not route messages through worker_controller
* Specify sources instead of targets like in storm?
* create a hybrid which can be both generating_worker to handle server
  requests and a processing_worker to receive the results (like in
  storm)
* ack messages to make sure all are processed
* Implement multi node/server support

HIGH priority
-------------
* move worker config to the start of the worker_controller (to work
  with dynamic workers)
    * should set callbackArgs in dynamically started workers
* Route messages in worker_controller to workers for
    * Hash on key X or a list of fields (from a record)
    
MEDIUM priority
---------------
* add checks for unsupported options in config_validator
* restrict the generating_workers if the processing_workers can't cope
  with the load (pull instead of push?)
* Consistent naming of WorkerConfig - CallbackConfig
* handle the simple_one_for_one workers (they do not die in sync with
  its sup)
    * start to use supervisor2 from rabbitmq-server
* improve performance for dynamic workers, a list might not be so good
  for 1000s of workers
* Add new worker_controllers dynamically, to allow for a process
  monitoring a directory for new files, then start a new
  generating_worker for each new file created in that directory. (more
  work to handle processing_worker than generating_worker)
    * Dynamically add/remove targets in a worker_controller
* Make it possible to stop worker_controller:s dynamically
* add possibility for worker to give ets table to worker_controller,
  requires the worker_controller to be passed as an argument in init
* Add possibility to reset all the workers, to start fresh without
  restarting all
* generalize processing_worker to another module to share code with
  generating_worker!
* Give the workers an id, starting from 1, and total worker count?
* Add infinity to all gen_server:calls
* check message queue size, have a way to report it
* remove WorkerMod from worker_controller and make the WorkerMods into
  behavior or at least force then to handle sync events, but what
  about the casting?
* Garbage collect dynamic workers (with empty state)?

LOW priority
------------
* Create a raw event generator which is spawned with a {M,F,A} and then
  it is on its own (possibly supervised via a supervisor_bridge)
* Extract the common code from the sup tests
* flaky tests:
    * <pre><code>
    master_tests: valid_topology_terget_ref_type_test...*failed*
    ::error:{assertMatch_failed,
              [{module,master_tests},
               {line,163},
               {expression,"master : start_link ( ValidTargetRefType2 )"},
               {expected,"{ ok , _Pid }"},
               {value,{error,{already_started,<0.875.0>}}}]}
      in function master_tests:'-valid_topology_terget_ref_type_test/0-fun-1-'/0
      in call from master_tests:valid_topology_terget_ref_type_test/0
    </code></pre>
    * <pre><code>
    worker_controller_tests: t_dynamic_workers_should_be_restarted_if_they_crash...*failed*
    ::error:{assertEqual_failed,
              [{module,worker_controller_tests},
               {line,232},
               {expression,
                   "meck : num_calls ( WorkerMod , process , [ NewWorker , Msg1 ] )"},
               {expected,1},
               {value,0}]}
      in function worker_controller_tests:'-t_dynamic_workers_should_be_restarted_if_they_crash/1-fun-1-'/3
      in call from worker_controller_tests:t_dynamic_workers_should_be_restarted_if_they_crash/1
      </code></pre>
* Stub processing_worker_sup in worker_controller_tests
* Make the processing_worker and generating_worker behaviour handle
  code_change
* Give the worker the possibility to change the timeout? (at end of
  file?)