resource "azurerm_public_ip" "publicip-ansible" {
  name                = "publicip-ansible"
  resource_group_name = azurerm_resource_group.aulainfra.name
  location            = azurerm_resource_group.aulainfra.location
  allocation_method   = "Static"

  tags = {
    turma = "as04"
    disciplina = "infra cloud"
    professor = "João"
  }
}

resource "azurerm_network_interface" "aula-nic-ansible" {
  name                = "aula-nic-ansible"
  location            = azurerm_resource_group.aulainfra.location
  resource_group_name = azurerm_resource_group.aulainfra.name

  ip_configuration {
    name                            = "internal"
    subnet_id                       = azurerm_subnet.subnet.id
    private_ip_address_allocation   = "Dynamic"
    public_ip_address_id            = azurerm_public_ip.publicip-ansible.id
  }
}

resource "azurerm_network_interface_security_group_association" "ng-nic-assoc-ansible" {
  network_interface_id      = azurerm_network_interface.aula-nic-ansible.id
  network_security_group_id = azurerm_network_security_group.infra-ng.id
}

resource "azurerm_linux_virtual_machine" "vm-ansible" {
  name                = "vm-ansible"
  resource_group_name = azurerm_resource_group.aulainfra.name
  location            = azurerm_resource_group.aulainfra.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.aula-nic-ansible.id
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.private-key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  depends_on = [
    local_file.private_key
  ]
}

data "azurerm_public_ip" "data-publicip-ansible" {
  name = azurerm_public_ip.publicip-ansible.name
  resource_group_name = azurerm_resource_group.aulainfra.name
}

resource "local_file" "create-inventory"{
    filename = "./ansible/inventory"
    content = <<EOF
[web]
${azurerm_network_interface.aula-nic.private_ip_address}

[web:vars]
ansible_user=adminuser
ansible_ssh_private_key_file=/home/adminuser/ansible/key.pem
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
    depends_on = [
      azurerm_linux_virtual_machine.vm
    ]
}

resource "null_resource" "upload-ansible-files"{
    provisioner "file" {
        connection {
            type = "ssh"
            host = data.azurerm_public_ip.data-publicip-ansible.ip_address
            user = "adminuser"
            private_key = tls_private_key.private-key.private_key_pem
        }
        source = "ansible"
        destination = "/home/adminuser"
    }

    depends_on = [
      local_file.create-inventory,
      azurerm_linux_virtual_machine.vm
    ]
}

resource "null_resource" "install-ansible" {
  triggers = {
    order = azurerm_linux_virtual_machine.vm-ansible.id
  }

  connection {
    type = "ssh"
    host = data.azurerm_public_ip.data-publicip-ansible.ip_address
    user = "adminuser"
    private_key = tls_private_key.private-key.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install -y software-properties-common",
      "sudo apt-add-repository --yes --update ppa:ansible/ansible",
      "sudo apt install -y python3 ansible"
    ]
  }

  depends_on = [
    azurerm_linux_virtual_machine.vm-ansible
  ]
}

resource "null_resource" "run-ansible" {
  triggers = {
    order = null_resource.upload-ansible-files.id
  }

  connection {
    type = "ssh"
    host = data.azurerm_public_ip.data-publicip-ansible.ip_address
    user = "adminuser"
    private_key = tls_private_key.private-key.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 400 /home/adminuser/ansible/key.pem",
      "ansible-playbook -i /home/adminuser/ansible/inventory /home/adminuser/ansible/playbook.yaml"
    ]
  }

  depends_on = [
    azurerm_linux_virtual_machine.vm-ansible,
    null_resource.install-ansible
  ]
}