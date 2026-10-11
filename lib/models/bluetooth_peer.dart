class BluetoothPeer {
  final String name;
  final String address;
  final bool isBonded;
  final String connectionState; // 'disconnected', 'connecting', 'connected', 'failed'
  final String? profileColor; // Hex string for styling
  final String? avatarInitials;
  final String? sharedKey;
  final String? customName;
  final String? profilePhoto;
  final String connectionStatus; // 'none', 'pending_sent', 'pending_received', 'approved'
  final String? notes; // Offline contact notes

  BluetoothPeer({
    required this.name,
    required this.address,
    required this.isBonded,
    this.connectionState = 'disconnected',
    this.profileColor,
    this.avatarInitials,
    this.sharedKey,
    this.customName,
    this.profilePhoto,
    this.connectionStatus = 'none',
    this.notes,
  });

  BluetoothPeer copyWith({
    String? name,
    String? address,
    bool? isBonded,
    String? connectionState,
    String? profileColor,
    String? avatarInitials,
    String? sharedKey,
    String? customName,
    String? profilePhoto,
    String? connectionStatus,
    String? notes,
  }) {
    return BluetoothPeer(
      name: name ?? this.name,
      address: address ?? this.address,
      isBonded: isBonded ?? this.isBonded,
      connectionState: connectionState ?? this.connectionState,
      profileColor: profileColor ?? this.profileColor,
      avatarInitials: avatarInitials ?? this.avatarInitials,
      sharedKey: sharedKey ?? this.sharedKey,
      customName: customName ?? this.customName,
      profilePhoto: profilePhoto ?? this.profilePhoto,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'bonded': isBonded ? 1 : 0,
      'color': profileColor,
      'initials': avatarInitials,
      'shared_key': sharedKey,
      'custom_name': customName,
      'profile_photo': profilePhoto,
      'connection_status': connectionStatus,
      'notes': notes,
    };
  }

  factory BluetoothPeer.fromMap(Map<String, dynamic> map) {
    return BluetoothPeer(
      name: map['name'] ?? '',
      address: map['address'] ?? '',
      isBonded: map['bonded'] == 1,
      profileColor: map['color'],
      avatarInitials: map['initials'],
      sharedKey: map['shared_key'],
      customName: map['custom_name'],
      profilePhoto: map['profile_photo'],
      connectionStatus: map['connection_status'] ?? 'none',
      notes: map['notes'],
    );
  }
}
