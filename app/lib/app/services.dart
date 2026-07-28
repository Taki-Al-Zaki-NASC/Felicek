import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../data/repositories/auth_repository.dart';
import '../data/repositories/chat_repository.dart';
import '../data/repositories/engagement_repository.dart';
import '../data/repositories/job_repository.dart';
import '../data/repositories/notification_repository.dart';
import '../data/repositories/proposal_repository.dart';
import '../data/repositories/user_repository.dart';
import '../data/repositories/wallet_repository.dart';
import '../data/services/call_service.dart';
import '../data/services/firestore_refs.dart';
import '../data/services/payment_gateway_service.dart';
import '../data/services/update_service.dart';

/// The app's dependency graph, built once at startup.
///
/// Everything is constructor-injected from here, so a test can swap in a fake
/// Firestore without touching feature code.
class AppServices {
  factory AppServices({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required UpdateService updateService,
  }) {
    // One `Db` — `ChatRepository` in particular keeps in-memory send-failure
    // state that must not be duplicated across instances.
    final Db db = Db(firestore);
    return AppServices._(
      auth: auth,
      firestore: firestore,
      updateService: updateService,
      db: db,
      authRepository: AuthRepository(auth: auth, db: db),
      userRepository: UserRepository(db),
      jobRepository: JobRepository(db),
      proposalRepository: ProposalRepository(db),
      chatRepository: ChatRepository(db),
      walletRepository: WalletRepository(db),
      notificationRepository: NotificationRepository(db),
      engagementRepository: EngagementRepository(db),
      paymentGatewayService: PaymentGatewayService(db),
      callService: CallService(db),
    );
  }

  const AppServices._({
    required this.auth,
    required this.firestore,
    required this.updateService,
    required this.db,
    required this.authRepository,
    required this.userRepository,
    required this.jobRepository,
    required this.proposalRepository,
    required this.chatRepository,
    required this.walletRepository,
    required this.notificationRepository,
    required this.engagementRepository,
    required this.paymentGatewayService,
    required this.callService,
  });

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final UpdateService updateService;
  final Db db;

  final AuthRepository authRepository;
  final UserRepository userRepository;
  final JobRepository jobRepository;
  final ProposalRepository proposalRepository;
  final ChatRepository chatRepository;
  final WalletRepository walletRepository;
  final NotificationRepository notificationRepository;
  final EngagementRepository engagementRepository;
  final PaymentGatewayService paymentGatewayService;
  final CallService callService;

  static AppServices of(BuildContext context) =>
      Provider.of<AppServices>(context, listen: false);
}

/// Convenience accessors so screens read `context.jobRepo` rather than
/// threading the locator through every constructor.
extension AppServicesX on BuildContext {
  AppServices get services => AppServices.of(this);

  AuthRepository get authRepo => services.authRepository;

  UserRepository get userRepo => services.userRepository;

  JobRepository get jobRepo => services.jobRepository;

  ProposalRepository get proposalRepo => services.proposalRepository;

  ChatRepository get chatRepo => services.chatRepository;

  WalletRepository get walletRepo => services.walletRepository;

  NotificationRepository get notificationRepo =>
      services.notificationRepository;

  EngagementRepository get engagementRepo => services.engagementRepository;

  UpdateService get updateService => services.updateService;

  PaymentGatewayService get paymentGateway => services.paymentGatewayService;

  CallService get callService => services.callService;
}
