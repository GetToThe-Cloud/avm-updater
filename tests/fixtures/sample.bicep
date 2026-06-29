// Test fixture: Bicep file with AVM module references
// Contains two res modules and one ptn module using mixed reference forms

targetScope = 'resourceGroup'

// --- res module using br/public short-hand ---
module storageAccount 'br/public:avm/res/storage/storage-account:0.4.0' = {
  name: 'myStorageAccount'
  params: {
    name: 'mystorageacct001'
    location: 'eastus'
  }
}

// --- res module using full MCR path ---
module keyVault 'br:mcr.microsoft.com/bicep/avm/res/key-vault/vault:0.6.2' = {
  name: 'myKeyVault'
  params: {
    name: 'mykeyvault001'
    location: 'eastus'
  }
}

// --- ptn module using br/public short-hand ---
module hubAndSpoke 'br/public:avm/ptn/network/hub-networking:0.1.3' = {
  name: 'myHubAndSpoke'
  params: {
    location: 'eastus'
  }
}
