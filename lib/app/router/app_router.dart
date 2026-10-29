import 'package:go_router/go_router.dart';

import '../../features/goals/goals_screen.dart';
import '../../features/goals/presentation/goal_detail_screen.dart';
import '../../features/goals/presentation/goal_form_screen.dart';
import '../../features/subjects/presentation/subject_detail_screen.dart';
import '../../features/subjects/presentation/subject_form_screen.dart';
import '../../features/tasks/presentation/task_form_screen.dart';
import '../../features/topics/presentation/topic_detail_screen.dart';
import '../../features/topics/presentation/topic_form_screen.dart';
import '../../presentation/progress/progress_screen.dart';
import '../../presentation/schedule/schedule_screen.dart';
import '../../presentation/settings/settings_screen.dart';
import '../../presentation/shell/main_shell.dart';
import '../../presentation/today/today_screen.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/today',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/today',
                builder: (context, state) => const TodayScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/goals',
                builder: (context, state) => const GoalsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/schedule',
                builder: (context, state) => const ScheduleScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/progress',
                builder: (context, state) => const ProgressScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/goals/new',
        builder: (context, state) => const GoalFormScreen(),
      ),
      GoRoute(
        path: '/goals/:goalId/subjects/new',
        builder: (context, state) =>
            SubjectFormScreen(goalId: state.pathParameters['goalId']!),
      ),
      GoRoute(
        path: '/goals/:goalId/subjects/:subjectId/topics/new',
        builder: (context, state) =>
            TopicFormScreen(subjectId: state.pathParameters['subjectId']!),
      ),
      GoRoute(
        path: '/goals/:goalId/subjects/:subjectId/topics/:topicId/tasks/new',
        builder: (context, state) =>
            TaskFormScreen(topicId: state.pathParameters['topicId']!),
      ),
      GoRoute(
        path: '/goals/:goalId/subjects/:subjectId/topics/:topicId',
        builder: (context, state) => TopicDetailScreen(
          goalId: state.pathParameters['goalId']!,
          subjectId: state.pathParameters['subjectId']!,
          topicId: state.pathParameters['topicId']!,
        ),
      ),
      GoRoute(
        path: '/goals/:goalId/subjects/:subjectId',
        builder: (context, state) => SubjectDetailScreen(
          goalId: state.pathParameters['goalId']!,
          subjectId: state.pathParameters['subjectId']!,
        ),
      ),
      GoRoute(
        path: '/goals/:goalId',
        builder: (context, state) =>
            GoalDetailScreen(goalId: state.pathParameters['goalId']!),
      ),
    ],
  );
}
