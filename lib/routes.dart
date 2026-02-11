// lib/routes.dart
import 'package:flutter/material.dart';
import 'package:fyp_tuition_eclassroom/screens/auth/forget_password.dart';
import 'package:fyp_tuition_eclassroom/screens/teacher/subject_detail.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/dashboards/student_dashboard.dart';
import 'screens/dashboards/teacher_dashboard.dart';
import 'screens/dashboards/admin_dashboard.dart';
import 'screens/admin/admin_user_management.dart';
import 'screens/teacher/create_quiz.dart';
import 'screens/teacher/create_subject.dart';
import 'screens/teacher/classroom_dashboard.dart';
import 'screens/teacher/create_assignment.dart';
import 'screens/teacher/assignment_detail.dart';
import 'screens/student/classroom/stu_classroom_dashboard.dart';
import 'screens/student/classroom/join_classroom_page.dart';
import 'screens/teacher/timetable/teacher_timetable_page.dart';
import 'screens/teacher/timetable/teacher_timetable_change_page.dart';
import 'screens/student/timetable/student_timetable_page.dart';
import 'screens/student/quiz/student_answer_quiz_page.dart';
import 'screens/settings_page.dart';
import 'screens/teacher/teacher_quiz_management_page.dart';

class Routes {
  static const String login = '/';
  static const String register = '/register';
  static const String home = '/home';
  static const String student = '/dashboard/student';
  static const String teacher = '/dashboard/teacher';
  static const String admin = '/dashboard/admin';
  static const String adminUsers = '/admin/users';
  static const String settings = '/settings';
  static const String forgotPassword = '/forgot-password';
  static const String createQuiz = '/create-quiz';
  static const String createSubject = '/create-subject';
  static const String assignmentDetail = '/assignment-detail';
  static const String classroomDashboard = '/classroom-dashboard';
  static const String subjectDetail = '/subject-detail';
  static const String createAssignment = '/create-assignment';
  static const String studentDashboard = '/student-dashboard';
  static const String studentClassroomDashboard = '/student-classroom-dashboard';
  static const String joinClassroom = '/join-classroom';
  static const String teacherTimetable = '/teacher-timetable';
  static const String teacherTimetableChange = '/teacher-timetable-change';
  static const String studentTimetable = '/student-timetable';
  static const String studentAnswerQuiz = '/student-answer-quiz';
  static const String teacherQuizManagement = '/teacher-quiz-management';











  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case register:
        return MaterialPageRoute(builder: (_) => const RegisterScreen());
      case home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case student:
        return MaterialPageRoute(builder: (_) => const StudentDashboard());
      case teacher:
        return MaterialPageRoute(builder: (_) => const TeacherDashboard());
      case admin:
        return MaterialPageRoute(builder: (_) => const AdminDashboard());
      case adminUsers:
        return MaterialPageRoute(builder: (_) => const AdminUserManagement());
      case studentDashboard:
        return MaterialPageRoute(builder: (_) => const StudentDashboard());
      case assignmentDetail:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => TeacherAssignmentDetailPage(
            assignmentData: args['assignmentData'],
            assignmentId: args['assignmentId'],
          ),
        );
      case createQuiz:
        return MaterialPageRoute(builder: (_) => CreateQuizPage());
      case createSubject:
        return MaterialPageRoute(builder: (_) => CreateClassroomPage());
      case classroomDashboard:
        return MaterialPageRoute(builder: (_) => ClassroomDashboard());
      case subjectDetail:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => SubjectDetailPage(classData: args['classData'],classId: args['classId']),
        );
      case createAssignment:
        final classId = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => CreateAssignmentPage(classId: classId),
        );
      case Routes.settings:
        return MaterialPageRoute(builder: (_) => const SettingsPage());
      case forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());
      case studentClassroomDashboard:
        return MaterialPageRoute(builder: (_) => const StudentClassroomDashboard());
      case joinClassroom:
        return MaterialPageRoute(builder: (_) => const JoinClassroomPage());
      case teacherTimetable:
        return MaterialPageRoute(builder: (_) => const TeacherTimetablePage());
      case teacherTimetableChange:
        return MaterialPageRoute(builder: (_) => const TeacherTimetableChangePage());
      case studentTimetable:
        return MaterialPageRoute(builder: (_) => const StudentTimetablePage());
      case studentAnswerQuiz:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => StudentAnswerQuizPage(
            quizId: args['quizId'],
            quizData: args['quizData'],
          ),
        );
      case teacherQuizManagement:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => TeacherQuizManagementPage(
            quizId: args['quizId'],
            quizData: args['quizData'],
            classId: args['classId'],
          ),
        );
      default:
        return MaterialPageRoute(
            builder: (_) => Scaffold(body: Center(child: Text('Unknown route'))));
    }
  }
}
