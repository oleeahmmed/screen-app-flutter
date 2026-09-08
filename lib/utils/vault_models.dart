/// Normalizes vault API payloads — mirrors aims-webapps `normalizeVault*`.

Map<String, dynamic> normalizeVaultCategory(Map<String, dynamic> c) {
  return {
    'id': c['id'],
    'name': c['name']?.toString() ?? '',
    'description': c['description']?.toString() ?? '',
    'customer_id': c['customer'] ?? c['customer_id'],
    'customer_name': c['customer_name']?.toString() ?? '',
    'project_id': c['project'] ?? c['project_id'],
    'created_by': c['created_by'] ?? c['createdBy'],
    'entry_count': c['entry_count'] ?? 0,
    'my_permission': c['my_permission'],
    'can_manage_entries': c['can_manage_entries'] == true,
    'can_admin': c['can_admin'] == true,
    'is_active': c['is_active'] != false,
    'created_at': c['created_at']?.toString() ?? '',
    'updated_at': c['updated_at']?.toString() ?? '',
  };
}

Map<String, dynamic> normalizeVaultEntry(Map<String, dynamic> e) {
  return {
    'id': e['id'],
    'name': e['name']?.toString() ?? '',
    'url': e['url']?.toString() ?? '',
    'username': e['username']?.toString() ?? '',
    'notes': e['notes']?.toString() ?? '',
    'category': e['category'] ?? e['category_id'],
    'category_name': e['category_name']?.toString() ?? '',
    'category_created_by': e['category_created_by'],
    'project': e['project'] ?? e['project_id'],
    'project_name': e['project_name']?.toString() ?? '',
    'created_by': e['created_by'] ?? e['createdBy'],
    'updated_by': e['updated_by'] ?? e['updatedBy'],
    'can_edit': e['can_edit'] == true,
    'can_delete': e['can_delete'] == true,
    'can_edit_secrets': e['can_edit_secrets'] == true,
    'can_edit_notes': e['can_edit_notes'] == true,
    'can_edit_attachments': e['can_edit_attachments'] == true,
    'is_favorite': e['is_favorite'] == true,
    'is_active': e['is_active'] != false,
    'attachments': e['attachments'] is List ? e['attachments'] : [],
    'shares': e['shares'] is List ? e['shares'] : [],
    'created_at': e['created_at']?.toString() ?? '',
    'updated_at': e['updated_at']?.toString() ?? '',
    'share_permission': e['share_permission'],
    'share_expires_at': e['share_expires_at'],
    'shared_by': e['shared_by'],
    'via_category_access': e['via_category_access'],
  };
}

bool vaultIsCreatedBy(Map<String, dynamic> item, int? userId) {
  if (userId == null) return false;
  final created = item['created_by'];
  if (created == null) return false;
  if (created is int) return created == userId;
  return int.tryParse('$created') == userId;
}
