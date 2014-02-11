# This is virtually identical to openstack-infra/config/modules/zuul/manifests/init.pp
# except I had to take out a few apache enmod resource blocks because Puppet is stupid
# and can't deal with the duplicate "resources" like turning on Apache mods.

class zuul (
  $vhost_name = $::fqdn,
  $serveradmin = "webmaster@${::fqdn}",
  $gearman_server = '127.0.0.1',
  $internal_gearman = true,
  $gerrit_server = '',
  $gerrit_user = '',
  $zuul_ssh_private_key = '',
  $url_pattern = '',
  $status_url = "https://${::fqdn}/",
  $zuul_url = '',
  $git_source_repo = 'https://git.openstack.org/openstack-infra/zuul',
  $push_change_refs = false,
  $job_name_in_report = false,
  $revision = 'master',
  $statsd_host = '',
  $replication_targets = []
) {
  include apache
  include pip

  $packages = [
    'python-webob',
    'python-lockfile',
    'python-paste',
  ]

  package { $packages:
    ensure => present,
  }

  # A lot of things need yaml, be conservative requiring this package to avoid
  # conflicts with other modules.
  if ! defined(Package['python-yaml']) {
    package { 'python-yaml':
      ensure => present,
    }
  }

  if ! defined(Package['python-paramiko']) {
    package { 'python-paramiko':
      ensure   => present,
    }
  }

  if ! defined(Package['python-daemon']) {
    package { 'python-daemon':
      ensure => present,
    }
  }

  user { 'zuul':
    ensure     => present,
    home       => '/home/zuul',
    shell      => '/bin/bash',
    gid        => 'zuul',
    managehome => true,
    require    => Group['zuul'],
  }

  group { 'zuul':
    ensure => present,
  }

  vcsrepo { '/opt/zuul':
    ensure   => latest,
    provider => git,
    revision => $revision,
    source   => $git_source_repo,
  }

  exec { 'install_zuul' :
    command     => 'pip install /opt/zuul',
    path        => '/usr/local/bin:/usr/bin:/bin/',
    refreshonly => true,
    subscribe   => Vcsrepo['/opt/zuul'],
    require     => Class['pip'],
  }

  file { '/etc/zuul':
    ensure => directory,
  }

# TODO: We should put in  notify either Service['zuul'] or Exec['zuul-reload']
#       at some point, but that still has some problems.
  file { '/etc/zuul/zuul.conf':
    ensure  => present,
    owner   => 'zuul',
    mode    => '0400',
    content => template('zuul/zuul.conf.erb'),
    require => [
      File['/etc/zuul'],
      User['zuul'],
    ],
  }

  file { '/etc/default/zuul':
    ensure  => present,
    mode    => '0444',
    content => template('zuul/zuul.default.erb'),
  }

  file { '/var/log/zuul':
    ensure  => directory,
    owner   => 'zuul',
    require => User['zuul'],
  }

  file { '/var/run/zuul':
    ensure  => directory,
    owner   => 'zuul',
    group   => 'zuul',
    require => User['zuul'],
  }

  file { '/var/lib/zuul':
    ensure  => directory,
    owner   => 'zuul',
    group   => 'zuul',
  }

  file { '/var/lib/zuul/git':
    ensure  => directory,
    owner   => 'zuul',
    require => File['/var/lib/zuul'],
  }

  file { '/var/lib/zuul/ssh':
    ensure  => directory,
    owner   => 'zuul',
    group   => 'zuul',
    mode    => '0500',
    require => File['/var/lib/zuul'],
  }

  file { '/var/lib/zuul/ssh/id_rsa':
    owner   => 'zuul',
    group   => 'zuul',
    mode    => '0400',
    require => File['/var/lib/zuul/ssh'],
    content => $zuul_ssh_private_key,
  }

  file { '/var/lib/zuul/www':
    ensure  => directory,
    require => File['/var/lib/zuul'],
  }

  package { 'libjs-jquery':
    ensure => present,
  }

  file { '/var/lib/zuul/www/jquery.min.js':
    ensure  => link,
    target  => '/usr/share/javascript/jquery/jquery.min.js',
    require => [File['/var/lib/zuul/www'],
                Package['libjs-jquery']],
  }

  vcsrepo { '/opt/jquery-visibility':
    ensure   => latest,
    provider => git,
    revision => 'master',
    source   => 'https://github.com/mathiasbynens/jquery-visibility.git',
  }

  file { '/var/lib/zuul/www/jquery-visibility.min.js':
    ensure  => link,
    target  => '/opt/jquery-visibility/jquery-visibility.min.js',
    require => [File['/var/lib/zuul/www'],
                Vcsrepo['/opt/jquery-visibility']],
  }

  file { '/var/lib/zuul/www/index.html':
    ensure  => link,
    target  => '/opt/zuul/etc/status/public_html/index.html',
    require => File['/var/lib/zuul/www'],
  }

  file { '/var/lib/zuul/www/app.js':
    ensure  => link,
    target  => '/opt/zuul/etc/status/public_html/app.js',
    require => File['/var/lib/zuul/www'],
  }

  file { '/etc/init.d/zuul':
    ensure => present,
    owner  => 'root',
    group  => 'root',
    mode   => '0555',
    source => 'puppet:///modules/zuul/zuul.init',
  }

  exec { 'zuul-reload':
    command     => '/etc/init.d/zuul reload',
    require     => File['/etc/init.d/zuul'],
    refreshonly => true,
  }

  service { 'zuul':
    name       => 'zuul',
    enable     => true,
    hasrestart => true,
    require    => File['/etc/init.d/zuul'],
  }

  cron { 'zuul_repack':
    user        => 'zuul',
    hour        => '4',
    minute      => '7',
    command     => 'find /var/lib/zuul/git/ -maxdepth 3 -type d -name ".git" -exec git --git-dir="{}" pack-refs --all \;',
    environment => 'PATH=/usr/bin:/bin:/usr/sbin:/sbin',
    require     => [User['zuul'],
                    File['/var/lib/zuul/git']],
  }

  apache::vhost { $vhost_name:
    port     => 443,
    docroot  => 'MEANINGLESS ARGUMENT',
    priority => '50',
    template => 'zuul/zuul.vhost.erb',
  }
}
