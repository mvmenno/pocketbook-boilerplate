/*
 * pb-launch - start an InkView app as a registered task and bring it to the
 * foreground. Runs on the device / inside pbemu (ARM, links libinkview).
 *
 *   pb-launch <path/to/app.app> [args...]   launch + activate
 *   pb-launch --activate <pid>              activate an already running task
 *
 * On 6.x firmware NewTaskEx() hands the request to monitor.app and returns 0
 * instead of the new task id, so we locate the task by its app path.
 */
#include <inkview.h>

static int find_task(const char *path)
{
    int tasks[64];
    int n = GetTaskList(tasks, 64);
    for (int i = 0; i < n; i++) {
        taskinfo *ti = GetTaskInfo(tasks[i]);
        if (ti && ti->appname && strcmp(ti->appname, path) == 0)
            return tasks[i];
    }
    return -1;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <app> [args...] | --activate <pid>\n", argv[0]);
        return 2;
    }

    InitInkview(TASK_NOHANDLER);

    int task = -1;
    if (strcmp(argv[1], "--activate") == 0 && argc > 2) {
        task = atoi(argv[2]);
    } else {
        const char *path = argv[1];
        task = find_task(path);
        if (task < 0) {
            if (NewTaskEx(path, argv + 1, path, NULL, NULL, 0, 0) < 0) {
                perror("NewTaskEx");
                return 1;
            }
            for (int i = 0; i < 100 && task < 0; i++) {
                usleep(100 * 1000);
                task = find_task(path);
            }
        }
        if (task < 0) {
            fprintf(stderr, "pb-launch: task for %s did not appear\n", path);
            return 1;
        }
    }

    int rc = SetActiveTask(task, 0);
    printf("task=%d activate_rc=%d\n", task, rc);
    return rc < 0 ? 1 : 0;
}
