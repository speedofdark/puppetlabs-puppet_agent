require 'spec_helper'

describe 'puppet_agent' do
  # All FOSS and all Puppet 4+ upgrades require the package_version
  package_version = '5.5.4'
  let(:params) {
    {
      :package_version => package_version
    }
  }

  let(:facts) do
    {
      :osfamily                  => 'RedHat',
      :architecture              => 'x64',
      :servername                => 'master.example.vm',
      :clientcert                => 'foo.example.vm',
    }
  end

  [['Fedora', 'fedora/f$releasever', 27], ['Fedora', 'fedora/f$releasever', 29], ['CentOS', 'el/$releasever', 7], ['Amazon', 'el/6', 6]].each do |os, urlbit, osmajor|
    context "with #{os} and #{urlbit}" do
      let(:facts) do
        super().merge(:operatingsystem  => os, :operatingsystemmajrelease => osmajor)
      end

      it { is_expected.to contain_exec('import-GPG-KEY-puppetlabs').with({
        'path'      => '/bin:/usr/bin:/sbin:/usr/sbin',
        'command'   => 'rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs',
        'unless'    => "rpm -q gpg-pubkey-`echo $(gpg --throw-keyids < /etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs) | cut --characters=11-18 | tr '[:upper:]' '[:lower:]'`",
        'require'   => 'File[/etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs]',
        'logoutput' => 'on_failure',
      }) }

      it { is_expected.to contain_exec('import-GPG-KEY-puppet').with({
        'path'      => '/bin:/usr/bin:/sbin:/usr/sbin',
        'command'   => 'rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-puppet',
        'unless'    => "rpm -q gpg-pubkey-`echo $(gpg --throw-keyids < /etc/pki/rpm-gpg/RPM-GPG-KEY-puppet) | cut --characters=11-18 | tr '[:upper:]' '[:lower:]'`",
        'require'   => 'File[/etc/pki/rpm-gpg/RPM-GPG-KEY-puppet]',
        'logoutput' => 'on_failure',
      }) }

      context 'with manage_pki_dir => true' do
        ['/etc/pki', '/etc/pki/rpm-gpg'].each do |path|
          it { is_expected.to contain_file(path).with({
            'ensure' => 'directory',
          }) }
        end
      end

      context 'with manage_pki_dir => false' do
        let(:params) {{ :manage_pki_dir => 'false' }}
        ['/etc/pki', '/etc/pki/rpm-gpg'].each do |path|
          it { is_expected.not_to contain_file(path) }
        end
      end

      it { is_expected.to contain_file('/etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs').with({
        'ensure' => 'present',
        'owner'  => '0',
        'group'  => '0',
        'mode'   => '0644',
        'source' => 'puppet:///modules/puppet_agent/GPG-KEY-puppetlabs',
      }) }

      it { is_expected.to contain_file('/etc/pki/rpm-gpg/RPM-GPG-KEY-puppet').with({
        'ensure' => 'present',
        'owner'  => '0',
        'group'  => '0',
        'mode'   => '0644',
        'source' => 'puppet:///modules/puppet_agent/GPG-KEY-puppet',
      }) }

      context 'when FOSS and manage_repo enabled' do
        let(:params)  {
          {
            :manage_repo => true,
            :package_version => package_version
          }
        }
        it { is_expected.not_to contain_yumrepo('puppetlabs-pepackages').with_ensure('absent') }
        it { is_expected.to contain_yumrepo('pc_repo').with({
          'baseurl' => "http://yum.puppetlabs.com/#{urlbit}/PC1/x64",
          'enabled' => 'true',
            'gpgcheck' => '1',
            'gpgkey' => "file:///etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs\n  file:///etc/pki/rpm-gpg/RPM-GPG-KEY-puppet",
        }) }

        it { is_expected.to contain_class("puppet_agent::osfamily::redhat") }
      end

      context 'when FOSS and manage_repo disabled' do
        let(:params)  {
          {
            :manage_repo => false,
            :package_version => package_version
          }
        }
        it { is_expected.not_to contain_yumrepo('puppetlabs-pepackages').with_ensure('absent') }
        it { is_expected.not_to contain_yumrepo('pc_repo')}

        it { is_expected.to contain_class("puppet_agent::osfamily::redhat") }
      end

      context 'when installing a puppet5 project' do
        let(:params)  {
          {
            :package_version => '5.2.0',
            :collection => 'puppet5'
          }
        }
        it { is_expected.to contain_yumrepo('pc_repo').with({
          # We no longer expect the 'f' in fedora repos
          'baseurl' => "http://yum.puppetlabs.com/puppet5/#{urlbit.gsub('/f','/')}/x64",
          'enabled' => 'true',
            'gpgcheck' => '1',
            'gpgkey' => "file:///etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs\n  file:///etc/pki/rpm-gpg/RPM-GPG-KEY-puppet",
        }) }
      end
    end
  end

  [['RedHat', 'el-7-x86_64', 'el-7-x86_64', 7], ['Amazon', '', 'el-6-x64', 6]].each do |os, tag, repodir, osmajor|
    context "when PE on #{os}" do
      before(:each) do
        # Need to mock the PE functions

        Puppet::Parser::Functions.newfunction(:pe_build_version, :type => :rvalue) do |args|
          '2000.0.0'
        end

        Puppet::Parser::Functions.newfunction(:pe_compiling_server_aio_build, :type => :rvalue) do |args|
          '5.5.4'
        end
      end

      let(:facts) do
        super().merge(
          :operatingsystem  => os,
          :operatingsystemmajrelease => osmajor,
          :platform_tag => tag,
          is_pe: true
        )
      end

      context 'with manage_repo enabled' do
        let(:params)  {
          {
            :manage_repo => true,
            :package_version => package_version
          }
        }

        it { is_expected.to contain_yumrepo('puppetlabs-pepackages').with_ensure('absent') }

        it { is_expected.to contain_yumrepo('pc_repo').with({
          'baseurl' => "https://master.example.vm:8140/packages/2000.0.0/#{repodir}",
          'enabled' => 'true',
          'gpgcheck' => '1',
          'gpgkey' => "file:///etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs\n  file:///etc/pki/rpm-gpg/RPM-GPG-KEY-puppet",
          'sslcacert' => '/etc/puppetlabs/puppet/ssl/certs/ca.pem',
          'sslclientcert' => '/etc/puppetlabs/puppet/ssl/certs/foo.example.vm.pem',
          'sslclientkey' => '/etc/puppetlabs/puppet/ssl/private_keys/foo.example.vm.pem',
          'skip_if_unavailable' => 'absent',
        }) }
        describe 'disable proxy' do
          let(:params) {
            {
              :manage_repo => true,
              :package_version => package_version,
              :disable_proxy   => true,
            }
          }
          it {
            is_expected.to contain_yumrepo('pc_repo').with_proxy('_none_')
          }
        end
        describe 'skip repo if unavailable' do
          let(:params) {
            {
              :manage_repo => true,
              :package_version => package_version,
              :skip_if_unavailable => true,
            }
          }
          it {
            is_expected.to contain_yumrepo('pc_repo').with_skip_if_unavailable(true)
          }
        end
      end

      context 'with manage_repo disabled' do
        let(:params)  {
          {
            :manage_repo => false,
            :package_version => package_version
          }
        }

        it { is_expected.to contain_yumrepo('puppetlabs-pepackages').with_ensure('absent') }

        it { is_expected.not_to contain_yumrepo('pc_repo')}
      end

      context 'with explicit package version' do
        let(:params)  {
          {
            :manage_repo => false,
            :package_version => package_version
          }
        }
        it { is_expected.to contain_package('puppet-agent').with_ensure("#{params[:package_version]}") }

      end

      it { is_expected.to contain_class("puppet_agent::osfamily::redhat") }
    end
  end
end
