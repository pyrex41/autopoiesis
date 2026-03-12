import { type Component, createSignal, createMemo, For, Show } from "solid-js";
import type { Task } from "../api/types";
import { taskStore } from "../stores/tasks";

interface CalendarTask extends Task {
  day: number;
  month: number;
  year: number;
}

const TaskCalendar: Component = () => {
  const [currentDate, setCurrentDate] = createSignal(new Date());

  const currentMonth = () => currentDate().getMonth();
  const currentYear = () => currentDate().getFullYear();

  // Get tasks with due dates (for now, we'll simulate due dates)
  // In a real implementation, tasks would have due_date fields
  const calendarTasks = createMemo(() => {
    const tasks = taskStore.filteredTasks();
    const month = currentMonth();
    const year = currentYear();

    return tasks.map((task, index) => ({
      ...task,
      // Simulate due dates - distribute tasks across the month
      day: Math.min(28, (index % 28) + 1),
      month,
      year,
    })) as CalendarTask[];
  });

  const daysInMonth = () => {
    return new Date(currentYear(), currentMonth() + 1, 0).getDate();
  };

  const firstDayOfMonth = () => {
    return new Date(currentYear(), currentMonth(), 1).getDay();
  };

  const monthNames = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
  ];

  const navigateMonth = (direction: 'prev' | 'next') => {
    const current = currentDate();
    const newDate = new Date(current);
    if (direction === 'prev') {
      newDate.setMonth(current.getMonth() - 1);
    } else {
      newDate.setMonth(current.getMonth() + 1);
    }
    setCurrentDate(newDate);
  };

  const getTasksForDay = (day: number) => {
    return calendarTasks().filter(task =>
      task.day === day &&
      task.month === currentMonth() &&
      task.year === currentYear()
    );
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'done': return 'bg-green-500';
      case 'in-progress': return 'bg-blue-500';
      case 'blocked': return 'bg-red-500';
      case 'pending': return 'bg-gray-400';
      default: return 'bg-gray-400';
    }
  };

  return (
    <div class="task-calendar">
      <div class="calendar-header">
        <button
          class="btn-nav"
          onClick={() => navigateMonth('prev')}
        >
          ‹
        </button>
        <h3 class="calendar-title">
          {monthNames[currentMonth()]} {currentYear()}
        </h3>
        <button
          class="btn-nav"
          onClick={() => navigateMonth('next')}
        >
          ›
        </button>
      </div>

      <div class="calendar-grid">
        {/* Day headers */}
        <For each={['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']}>
          {(dayName) => (
            <div class="calendar-day-header">{dayName}</div>
          )}
        </For>

        {/* Empty cells for days before the first day of month */}
        <For each={Array(firstDayOfMonth())}>
          {() => <div class="calendar-day empty"></div>}
        </For>

        {/* Days of the month */}
        <For each={Array(daysInMonth())}>
          {(_, index) => {
            const day = index() + 1;
            const dayTasks = getTasksForDay(day);

            return (
              <div class="calendar-day">
                <div class="day-number">{day}</div>
                <div class="day-tasks">
                  <For each={dayTasks.slice(0, 3)}>
                    {(task) => (
                      <div
                        class={`task-item ${getStatusColor(task.status)}`}
                        title={`${task.title} (${task.status})`}
                        onClick={() => taskStore.selectTask(task.id)}
                      >
                        {task.id}
                      </div>
                    )}
                  </For>
                  <Show when={dayTasks.length > 3}>
                    <div class="task-item more">
                      +{dayTasks.length - 3} more
                    </div>
                  </Show>
                </div>
              </div>
            );
          }}
        </For>
      </div>

      <div class="calendar-legend">
        <div class="legend-item">
          <div class="legend-color bg-green-500"></div>
          <span>Done</span>
        </div>
        <div class="legend-item">
          <div class="legend-color bg-blue-500"></div>
          <span>In Progress</span>
        </div>
        <div class="legend-item">
          <div class="legend-color bg-red-500"></div>
          <span>Blocked</span>
        </div>
        <div class="legend-item">
          <div class="legend-color bg-gray-400"></div>
          <span>Pending</span>
        </div>
      </div>
    </div>
  );
};

export default TaskCalendar;