# @summary Apply this class to a node running puppetdb to collect puppetdb metrics
#
# @param timeout
#   Default timeout of http calls.  Defaults to 5 seconds
#
# @param puppetdb_metrics
#   An array of hashes containing name / url pairs for each puppetdb metric.
#   See functions/puppetdb_metrics.pp for defaults.
#
# @param puppetdb_host
#   Where to query the puppetdb host.  Defaults to localhost.
#
# @param port
#   The port that the puppetdb service listens on on your compiler.  Defaults to 8081
#
# @param interval
#   The frequency that telegraf will poll for metrics.  Defaults to '5s'
#
# @param enable_client_cert
#   A boolean to enable using the client certificate for the PuppetDB queries. Defaults to true
#
# @param influxdb_host
#   The hostname of the InfluxDB server to send metrics to. Only used if running telegraf remotely. Defaults to `undef`
#
# @param influxdb_database
#   The name of the database to use in InfluxDB. Defaults to the hiera value of `'puppet_metrics_dashboard::telegraf_db_name`
#
# @example Add telegraf to a puppetdb node
#   puppet_metrics_dashboard::profile::puppetdb{ $facts['networking']['fqdn']:
#     timeout          => '5s',
#     puppetdb_metrics => puppet_metrics_dashboard::puppetdb_metrics(), # this is the default value
#     influxdb_host    => 'dashboard.example.com', # the node that is classified with the `puppet_metrics_dashboard` class.
#   }
#
define puppet_metrics_dashboard::profile::puppetdb (
  String[2] $timeout                                          = lookup('puppet_metrics_dashboard::http_response_timeout'),
  Variant[String,Tuple[String, Integer]] $puppetdb_host       = 'localhost',
  Puppet_metrics_dashboard::Puppetdb_metric $puppetdb_metrics = puppet_metrics_dashboard::puppetdb_metrics(),
  Integer[1] $port                                            = 8081,
  String[2] $interval                                         = '5s',
  Boolean $enable_client_cert                                 = true,
  Optional[String[1]] $influxdb_host                          = undef,
  String[1] $influxdb_database                                = lookup('puppet_metrics_dashboard::telegraf_db_name'),
  ){

  if $influxdb_host {

    class { 'telegraf':
      hostname => $trusted['certname'],
      interval => '5s',
      logfile  => '/var/log/telegraf/telegraf.log',
      outputs  => {
        'influxdb' => [{
            'urls'              => ["http://${influxdb_host}:8086"],
            'database'          => $influxdb_database,
            'write_consistency' => 'any',
            'timeout'           => '5s',
          }],
      },
    }

  }

  ensure_resource( 'puppet_metrics_dashboard::certs', 'telegraf', {
      notify  => Service['telegraf'],
      require => Package['telegraf'],
      before  => Service['telegraf'],
  })

  $cert_dir = '/etc/telegraf'
  $default_options = $enable_client_cert ? {
    true => {
      'tls_key'              => "${cert_dir}/${clientcert}_key.pem",
      'tls_cert'             => "${cert_dir}/${clientcert}_cert.pem",
      'tls_ca'               => "${cert_dir}/ca.pem",
      'insecure_skip_verify' => false,
    },
    default => {
      'insecure_skip_verify' => true,
    }
  }

  if puppet_metrics_dashboard::puppetdb_no_remote_metrics() {
        $metrics_version = 'v2/read'
      } else {
        $metrics_version = 'v1/mbeans'
      }

  $puppetdb_metrics.each |$metric| {
    telegraf::input { "puppetdb_${metric['name']}_${puppetdb_host}":
      plugin_type => 'httpjson',
      options     => [{
        'name'             => "puppetdb_${metric['name']}",
        'method'           => 'GET',
        'servers'          => [ "https://${puppetdb_host}:${port}/metrics/${metrics_version}/${metric['url']}" ],
        'response_timeout' => $timeout,
        } + $default_options
      ],
      notify      => Service['telegraf'],
      require     => Package['telegraf'],
    }
  }

  telegraf::input { "puppetdb_command_queue_${puppetdb_host}":
    plugin_type => 'httpjson',
    options     => [{
      'name'             => 'puppetdb_command_queue',
      'servers'          => [ "https://${puppetdb_host}:${port}/status/v1/services?level=debug" ],
      'response_timeout' => $timeout,
      } + $default_options
    ],
    notify      => Service['telegraf'],
    require     => Package['telegraf'],
  }
}
