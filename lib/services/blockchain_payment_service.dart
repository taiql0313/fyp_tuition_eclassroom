import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp_tuition_eclassroom/models/payment_models.dart';
import 'package:http/http.dart' as http;
import 'package:wallet/wallet.dart' show EthereumAddress, EtherAmount;
import 'package:web3dart/web3dart.dart';

class BlockchainPaymentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Use 10.0.2.2 for Android emulator to reach host machine's localhost
  static const String _ganacheRpcUrl = 'http://10.0.2.2:7545';
  // Ganache default chain ID is 1337 (network ID 5777 is different from chain ID)
  static const int _ganacheChainId = 1337;

  // The tuition center's receiving wallet (first Ganache account by default)
  static const String receiverAddress =
      '0x9e101E2edBE86e75BE25F9B4222f4e1Ac4B6707C';

  static const double _myrToEthRate = 0.00013;

  double convertMyrToEth(double amountMyr) {
    final converted = amountMyr * _myrToEthRate;
    return double.parse(converted.toStringAsFixed(6));
  }

  Web3Client _getClient() {
    return Web3Client(_ganacheRpcUrl, http.Client());
  }

  Future<EtherAmount> getBalance(String address) async {
    final client = _getClient();
    try {
      final balance =
          await client.getBalance(EthereumAddress.fromHex(address));
      return balance;
    } finally {
      client.dispose();
    }
  }

  Future<Map<String, dynamic>> processBlockchainPayment({
    required String invoiceId,
    required double amountMyr,
    required String studentId,
    required String studentName,
    required String senderAddress,
    required String privateKey,
  }) async {
    final client = _getClient();

    try {
      final ethAmount = convertMyrToEth(amountMyr);
      final weiAmount = BigInt.from(ethAmount * pow(10, 18));

      final credentials = EthPrivateKey.fromHex(privateKey);
      final credentialAddress = credentials.address;

      if (credentialAddress.with0x.toLowerCase() !=
          senderAddress.toLowerCase()) {
        throw Exception(
            'Private key does not match the provided wallet address');
      }

      final balance = await client.getBalance(credentialAddress);
      if (balance.getInWei < weiAmount) {
        throw Exception(
            'Insufficient balance. You need at least $ethAmount ETH');
      }

      final transaction = PaymentTransaction(
        id: '',
        invoiceId: invoiceId,
        studentId: studentId,
        studentName: studentName,
        amount: amountMyr,
        paymentMethod: 'blockchain',
        status: 'pending',
        createdAt: DateTime.now(),
        blockchainFromAddress: senderAddress,
        blockchainToAddress: receiverAddress,
        blockchainAmountEth: ethAmount,
        blockchainNetwork: 'Ganache Local',
      );

      final docRef = await _db
          .collection('payment_transactions')
          .add(transaction.toMap());

      final txHash = await client.sendTransaction(
        credentials,
        Transaction(
          to: EthereumAddress.fromHex(receiverAddress),
          value: EtherAmount.inWei(weiAmount),
          gasPrice: EtherAmount.inWei(BigInt.from(20000000000)),
          maxGas: 21000,
        ),
        chainId: _ganacheChainId,
      );

      await _db.collection('payment_transactions').doc(docRef.id).update({
        'status': 'completed',
        'blockchainTxHash': txHash,
        'completedAt': FieldValue.serverTimestamp(),
      });

      await _db.collection('invoices').doc(invoiceId).update({
        'status': 'paid',
        'paidAt': FieldValue.serverTimestamp(),
        'paymentTransactionId': docRef.id,
        'studentId': studentId,
      });

      await _logPaymentEvent(
        action: 'Blockchain Payment Completed',
        details: 'ETH payment of $ethAmount ETH (RM ${amountMyr.toStringAsFixed(2)}) '
            'for invoice $invoiceId. Tx: $txHash',
      );

      return {
        'transactionId': docRef.id,
        'txHash': txHash,
        'ethAmount': ethAmount,
      };
    } catch (e) {
      rethrow;
    } finally {
      client.dispose();
    }
  }

  Future<void> _logPaymentEvent({
    required String action,
    required String details,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      final data = doc.data();
      final name = data?['displayName'] as String? ??
          user.displayName ??
          user.email ??
          'User';
      final role = data?['role'] as String? ?? 'user';

      await _db.collection('system_logs').add({
        'type': 'Info',
        'category': 'Fees & Payment',
        'action': action,
        'user': name,
        'role': role,
        'userId': user.uid,
        'details': details,
        'success': true,
        'time': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error logging blockchain payment event: $e');
    }
  }
}
