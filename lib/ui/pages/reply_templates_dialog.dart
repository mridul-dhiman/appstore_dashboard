part of 'reviews_tab.dart';

/// Add, rename, rewrite or remove this client's reply templates. `{name}` becomes the reviewer's nickname.
class TemplatesDialog extends StatefulWidget {
  const TemplatesDialog({super.key, required this.templates});
  final ReplyTemplates templates;

  @override
  State<TemplatesDialog> createState() => _TemplatesDialogState();
}

class _TemplatesDialogState extends State<TemplatesDialog> {
  late final _rows = [
    for (final e in widget.templates.items.entries) (TextEditingController(text: e.key), TextEditingController(text: e.value)),
  ];

  @override
  void dispose() {
    for (final (a, b) in _rows) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reply templates'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Write {name} where the reviewer\'s nickname should go. Saved on this Mac for this client.'),
              const SizedBox(height: 14),
              for (var i = 0; i < _rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 150,
                        child: TextField(
                          controller: _rows[i].$1,
                          decoration: const InputDecoration(labelText: 'Name'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _rows[i].$2,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(labelText: 'Reply'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        onPressed: () => setState(() {
                          final (a, b) = _rows.removeAt(i);
                          a.dispose();
                          b.dispose();
                        }),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: () => setState(() => _rows.add((TextEditingController(), TextEditingController(text: 'Hi {name}, ')))),
                icon: const Icon(Icons.add),
                label: const Text('Add template'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            await widget.templates.save({for (final (a, b) in _rows) a.text: b.text});
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
