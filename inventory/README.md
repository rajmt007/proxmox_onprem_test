# Environment inventory

`environment-inventory.xlsx` contains the required `Envir` worksheet. The two requested Proxmox node addresses are marked `PROPOSED`, not active, because the host LAN, DHCP reservations, and existing-device state could not be inspected from this build environment.

Before any installation:

1. Review the workbook and preserve existing inventory records.
2. Confirm target address ownership/availability using the authoritative DHCP/router reservation system and a live LAN check. A failed ping is not proof that an IP is unused.
3. Fill subnet prefix, gateway, DNS, VLAN/network, owner, VM IDs, and status only from verified information.
4. Change a proposed record to `ACTIVE` only after the machine is installed and observed.

Required columns: `MachineName`, `Role`, `Hypervisor`, `IP_Address`, `Subnet_Prefix`, `Gateway`, `DNS`, `VLAN_or_Network`, `VM_ID`, `OS`, `Status`, `Owner`, `Last_Checked`, `Notes`.

The automation reads `.xlsx`, `.xlsm`, `.csv`, and `.json` inventory sources using standard-library parsing and reports whether a source or the `Envir` worksheet is missing. Do not commit private inventory files containing sensitive details.
