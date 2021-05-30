    sudo bash
    cd /usr/src
    git clone https://github.com/frankcrawford/it87
    ./dkms-install.sh

It's required to add both `ignore_resource_conflict=1` and `acpi_enforce_resources=lax` to kernel boot parameters, `ignore_resource_conflict=1` by itself doesn't always work.

To load the module on boot:

    #/etc/modules-load.d/it87.conf
    it87
