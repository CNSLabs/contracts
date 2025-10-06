# Storage Layouts

This directory contains storage layout snapshots for upgradeable contracts.

## Usage

Generate layout:
```bash
forge inspect CNSTokenL2 storage-layout > layouts/CNSTokenL2-v1.json
```

Compare before upgrading:
```bash
diff layouts/CNSTokenL2-v1.json layouts/CNSTokenL2-v2.json
```
