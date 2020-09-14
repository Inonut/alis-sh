build-box:
	packer build -force alis.pkr.hcl

test-vagrant:
	vagrant box add output_box/alis-virtualbox-*.box --force --name alis
	vagrant destroy -f
	vagrant up
