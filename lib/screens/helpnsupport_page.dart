import 'package:flutter/material.dart';
// Adjust this import to match your file structure for the AI page
import 'student/ai_support_page.dart';

class FaqPage extends StatefulWidget {
  const FaqPage({super.key});

  @override
  State<FaqPage> createState() => _FaqPageState();
}

class _FaqPageState extends State<FaqPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  // --- EXPANDED FAQ DATA ---
  final List<Map<String, String>> _faqs = [
    // Account & General
    {
      "category": "Account",
      "question": "How do I reset my password?",
      "answer": "Currently, password resets are handled by the Admin. Please contact the administration office or use the 'Contact Admin' button. In future updates, a self-service 'Forgot Password' link will be available."
    },
    {
      "category": "Account",
      "question": "Can I change my profile picture?",
      "answer": "Yes. Go to your Profile settings in the Dashboard and tap on the camera icon to upload a new photo."
    },

    // Attendance
    {
      "category": "Attendance",
      "question": "How is attendance recorded?",
      "answer": "Teachers generate a unique session code at the start of class. You must enter this code in the 'Attendance' section of your Dashboard to check in."
    },
    {
      "category": "Attendance",
      "question": "I forgot to check in on time. What should I do?",
      "answer": "If the session code has expired, your attendance will be marked as 'Absent'. Please inform your teacher immediately so they can manually update your status."
    },
    {
      "category": "Attendance",
      "question": "How do I submit a Medical Certificate (MC)?",
      "answer": "Go to the 'Attendance' page, select 'Submit MC', and upload a clear photo or PDF of your document along with the date of absence."
    },

    // Fees & Payments
    {
      "category": "Fees",
      "question": "Can I download receipts for my fees?",
      "answer": "Yes. Navigate to the 'Payments' section. Click on any 'Paid' invoice to view and download the official receipt PDF."
    },
    {
      "category": "Fees",
      "question": "What payment methods are supported?",
      "answer": "We support online banking (FPX), credit/debit cards via PayPal, and manual bank transfer uploads."
    },

    // Academics (Assignments/Materials)
    {
      "category": "Academics",
      "question": "Where can I find my class materials?",
      "answer": "Go to your Dashboard and click on the 'Resources' tile. You will find folders for each subject you are enrolled in."
    },
    {
      "category": "Academics",
      "question": "What file formats can I upload for assignments?",
      "answer": "The system accepts PDF, DOCX, JPG, and PNG files. Please ensure your file size is under 10MB."
    },
    {
      "category": "Academics",
      "question": "Can I resubmit an assignment?",
      "answer": "Yes, as long as the deadline has not passed. Simply upload the new file, and it will replace the previous submission."
    },

    // Communication
    {
      "category": "Communication",
      "question": "How do I contact my teacher?",
      "answer": "You can start a private chat with your teacher via the 'Messages' tile on your dashboard. For general updates, check the 'Announcements' section."
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Filter logic
    final filteredFaqs = _faqs.where((faq) {
      final q = faq['question']!.toLowerCase();
      final a = faq['answer']!.toLowerCase();
      final c = faq['category']!.toLowerCase();
      final search = _searchQuery.toLowerCase();
      return q.contains(search) || a.contains(search) || c.contains(search);
    }).toList();

    return Scaffold(
      // Floating Action Button for AI Support
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AiSupportPage()),
          );
        },
        backgroundColor: const Color(0xff1458a3),
        icon: const Icon(Icons.auto_awesome, color: Colors.white),
        label: const Text("Ask AI Tutor", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: CustomScrollView(
        slivers: [
          // --- 1. Sliver App Bar with Search ---
          SliverAppBar(
            expandedHeight: 180.0,
            floating: false,
            pinned: true,
            backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).colorScheme.primary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xff1458a3), Color(0xff4a90e2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.help_outline_rounded, size: 48, color: Colors.white24),
                        const SizedBox(height: 8),
                        Text(
                          "How can we help?",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(70),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: "Search for answers...",
                    prefixIcon: const Icon(Icons.search, color: Color(0xff1458a3)),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    // Using styled border instead:
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // --- 1.5 Header for FAQ Section ---
          if (filteredFaqs.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xff1458a3).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.quiz_rounded, color: Color(0xff1458a3), size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "Frequently Asked Questions",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xff2d3436),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // --- 2. FAQ List ---
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: filteredFaqs.isEmpty
                ? SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 50.0),
                  child: Column(
                    children: [
                      Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text("No results found", style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                      const SizedBox(height: 8),
                      Text("Try searching for 'Fees' or 'Attendance'", style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                    ],
                  ),
                ),
              ),
            )
                : SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final faq = filteredFaqs[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xffe7f0ff),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _getCategoryIcon(faq['category']!),
                            color: const Color(0xff1458a3),
                            size: 20,
                          ),
                        ),
                        title: Text(
                          faq['question']!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Color(0xff2d3436),
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            faq['category']!,
                            style: TextStyle(color: Colors.grey[400], fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FA),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                faq['answer']!,
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  height: 1.5,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: filteredFaqs.length,
              ),
            ),
          ),

          // --- 3. Bottom Contact Section ---
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 100), // Bottom padding for FAB
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.shade50),
              ),
              child: Column(
                children: [
                  const Text(
                    "Still need help?",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Our AI Tutor is available 24/7 to assist you with academic questions or system issues.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () {
                      // TODO: Implement direct email support or ticket system
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Email support: support@tuition.edu.my"))
                      );
                    },
                    icon: const Icon(Icons.email_outlined),
                    label: const Text("Contact Support Team"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xff1458a3),
                      side: const BorderSide(color: Color(0xff1458a3)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Fees': return Icons.payments_outlined;
      case 'Attendance': return Icons.calendar_today_outlined;
      case 'Academics': return Icons.menu_book_outlined;
      case 'Communication': return Icons.chat_bubble_outline;
      case 'Account': return Icons.person_outline;
      default: return Icons.help_outline;
    }
  }
}