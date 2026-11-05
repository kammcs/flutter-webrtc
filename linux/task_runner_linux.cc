#include "task_runner_linux.h"

#include <glib.h>

namespace flutter_webrtc_plugin {

void TaskRunnerLinux::EnqueueTask(TaskClosure task) {
  {
    std::lock_guard<std::mutex> lock(tasks_mutex_);
    tasks_.push(std::move(task));
  }

  GMainContext* context = g_main_context_default();
  if (context) {
    g_main_context_invoke(
        context,
        [](gpointer user_data)  -> gboolean {
          TaskRunnerLinux* runner = static_cast<TaskRunnerLinux*>(user_data);
          // Take the queued tasks, then run them without holding the lock. A
          // task may enqueue another one (a method result answered from a
          // task, for example), which would otherwise deadlock on
          // tasks_mutex_ and hang the platform thread.
          std::queue<TaskClosure> tasks;
          {
            std::lock_guard<std::mutex> lock(runner->tasks_mutex_);
            std::swap(tasks, runner->tasks_);
          }
          while (!tasks.empty()) {
            TaskClosure task = std::move(tasks.front());
            tasks.pop();
            task();
          }
          return G_SOURCE_REMOVE;
        },
        this);
  }
}

}  // namespace flutter_webrtc_plugin
