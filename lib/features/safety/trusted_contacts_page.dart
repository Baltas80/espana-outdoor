import 'package:flutter/material.dart';

import '../../core/emergency/trusted_contact.dart';
import '../../core/emergency/trusted_contact_store.dart';
import '../../app/design_system/eo_icon_library.dart';

class TrustedContactsPage extends StatefulWidget {
  const TrustedContactsPage({super.key});

  @override
  State<TrustedContactsPage> createState() => _TrustedContactsPageState();
}

class _TrustedContactsPageState extends State<TrustedContactsPage> {
  final _store = TrustedContactStore();
  late List<TrustedContact> _contacts;

  @override
  void initState() {
    super.initState();
    _contacts = _store.load().toList();
  }

  Future<void> _addContact() async {
    final form = GlobalKey<FormState>();
    final name = TextEditingController();
    final phone = TextEditingController();

    final result = await showDialog<TrustedContact>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo contacto'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Ej. Ana',
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty
                        ? 'Introduce un nombre'
                        : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  hintText: '+34 600 000 000',
                ),
                validator: (value) =>
                    value == null || value.trim().length < 6
                        ? 'Introduce un teléfono válido'
                        : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(
                context,
                TrustedContact(
                  id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
                  displayName: name.text.trim(),
                  phone: phone.text.trim(),
                ),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    name.dispose();
    phone.dispose();

    if (result == null) return;
    if (_contacts.length >= 5) {
      _show('Máximo de 5 contactos de confianza.');
      return;
    }

    final duplicate = _contacts.any((item) => item.phone == result.phone);
    if (duplicate) {
      _show('Ese teléfono ya está configurado.');
      return;
    }

    setState(() => _contacts.add(result));
    await _store.save(_contacts);
  }

  Future<void> _removeContact(TrustedContact contact) async {
    setState(() => _contacts.removeWhere((item) => item.id == contact.id));
    await _store.save(_contacts);
  }

  Future<void> _toggleContact(TrustedContact contact) async {
    final index = _contacts.indexWhere((item) => item.id == contact.id);
    if (index < 0) return;

    final updated = TrustedContact(
      id: contact.id,
      displayName: contact.displayName,
      phone: contact.phone,
      email: contact.email,
      enabled: !contact.enabled,
    );
    setState(() => _contacts[index] = updated);
    await _store.save(_contacts);
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contactos de confianza')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContact,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Añadir'),
      ),
      body: _contacts.isEmpty
          ? const _EmptyContacts()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              itemCount: _contacts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final contact = _contacts[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        contact.displayName.isEmpty
                            ? '?'
                            : contact.displayName.substring(0, 1).toUpperCase(),
                      ),
                    ),
                    title: Text(
                      contact.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(contact.phone),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'toggle') _toggleContact(contact);
                        if (action == 'delete') _removeContact(contact);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(
                            contact.enabled ? 'Desactivar' : 'Activar',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Eliminar'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EOIcon(EOIconName.contacts, size: 72),
            const SizedBox(height: 16),
            Text(
              'Aún no hay contactos',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Añade personas que puedan recibir una alerta temporal '
              'cuando tú lo confirmes.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
