require 'rspec'

namespace :fly do
  # bundle exec rake fly:unit
  desc 'Fly unit specs'
  task :unit do
    db, db_version = fetch_db_and_version

    execute('test-unit', command_opts('unit', db, db_version),
            DB: db, DB_VERSION: db_version,
            COVERAGE: ENV.fetch('COVERAGE', false))
  end

  # bundle exec rake fly:integration
  desc 'Fly integration specs'
  task :integration, [:cli_dir] do |_, args|
    db, db_version = fetch_db_and_version

    command_opts = command_opts('integration', db, db_version)
    command_opts += " --input bosh-cli=#{args[:cli_dir]}" if args[:cli_dir]

    execute('test-integration', command_opts,
            DB: db, DB_VERSION: db_version,
            SPEC_PATH: ENV.fetch('SPEC_PATH', nil))
  end

  # bundle exec rake fly:run["pwd ; ls -al"]
  task :run, [:command] do |_, args|
    execute('run', '--privileged',
            COMMAND: %(\"#{args[:command]}\"))
  end

  private

  def fetch_db_and_version
    db = ENV.fetch('DB', 'postgresql')

    case db
    when 'postgresql'
      db_version = ENV.fetch('DB_VERSION', '15')
    when 'mysql'
      db_version = ENV.fetch('DB_VERSION', '8.0')
    when 'sqlite'
      db_version = nil
    else
      fail "invalid DB: '#{db}'"
    end

    [db, db_version]
  end

  def command_opts(test_type, db, db_version)
    [
      "--privileged",
      input_from(test_type, db),
      image(db, db_version)
    ].join(' ')
  end

  def db_short_name(db)
    db == 'postgresql' ? 'postgres' : db
  end

  def input_from(test_type, db)
    case test_type
    when 'unit'
      if db == 'sqlite'
        '--inputs-from bosh-director/unit'
      else
        "--inputs-from bosh-director/#{test_type}-#{db_short_name(db)}"
      end

    when 'integration'
      "--inputs-from bosh-director/#{test_type}-#{db_short_name(db)}"

    else
      fail "invalid test_type: '#{test_type}'"
    end
  end

  def image(db, db_version)
    if db == 'sqlite'
      '--image integration-image'
    else
      "--image integration-#{db_short_name(db)}-#{db_version.gsub('.', '-')}-image"
    end
  end

  def concourse_tag
    tag = ENV.fetch('CONCOURSE_TAG', '')
    "--tag=#{tag}" unless tag.empty?
  end

  def concourse_target
    "--target #{ENV.fetch('CONCOURSE_TARGET', 'director')}"
  end

  def prepare_env(additional_env = {})
    env = {
      RUBY_VERSION: ENV['RUBY_VERSION'] || RUBY_VERSION,
    }
    env.merge!(additional_env)

    env.to_a.map { |pair| pair.join('=') }.join(' ')
  end

  def execute(task, command_options = nil, additional_env = {})
    env = prepare_env(additional_env)
    sh("#{env} fly #{concourse_target} sync")
    sh(
      "#{env} fly #{concourse_target} execute #{concourse_tag} #{command_options} -c ../ci/tasks/#{task}.yml -i bosh-src=$PWD/../",
    )
  end
end

desc 'Fly unit and integration specs'
task fly: %w[fly:unit fly:integration]
