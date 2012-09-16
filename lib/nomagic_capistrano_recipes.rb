require "nomagic_capistrano_recipes/version"

module NomagicCapistranoRecipes

  Capistrano::Configuration.instance(:must_exist).load do
    set :enable_local_db_export, false
    set :enable_local_asset_export, false

    namespace :import do
      desc "Dump remote database and import to local"
      task :remote_database do
        puts "-----------------------------------------------------------------------------------------"
        puts "Importing database from #{domain} to local machine"
        puts "-----------------------------------------------------------------------------------------"

        get("#{shared_path}/config/database.yml", "tmp/#{stage}-database.yml")

        remote_settings = YAML::load_file("tmp/#{stage}-database.yml")["#{rails_env}"]
        local_settings = YAML::load_file("config/database.yml")["development"]

        # Dump on remote
        puts "-----------------------------------------------------------------------------------------"
        puts "Dumping database on #{domain}"
        puts "-----------------------------------------------------------------------------------------"
        run "mysqldump -u#{remote_settings["username"]} #{"-p#{remote_settings["password"]}" if remote_settings["password"]} #{"-h#{remote_settings['host']}" if remote_settings['host']} #{remote_settings["database"]} > #{shared_path}/tmp/#{stage}-#{remote_settings["database"]}-dump.sql"

        # Rsync to local
        puts "-----------------------------------------------------------------------------------------"
        puts "Rsyncing database from #{domain} to local"
        puts "-----------------------------------------------------------------------------------------"
        run_locally("rsync --times --rsh='ssh -p#{port}' --compress --human-readable --progress #{user}@#{domain}:#{shared_path}/tmp/#{stage}-#{remote_settings["database"]}-dump.sql tmp/#{stage}-#{remote_settings["database"]}-dump.sql")

        # Update database on local
        puts "-----------------------------------------------------------------------------------------"
        puts "Updating database on local"
        puts "-----------------------------------------------------------------------------------------"
        run_locally("mysql -u#{local_settings["username"]} #{"-p#{local_settings["password"]}" if local_settings["password"]} #{"-h#{local_settings['host']}" if local_settings['host']} #{local_settings["database"]} < tmp/#{stage}-#{remote_settings["database"]}-dump.sql")

        # Remove temporary files
        puts "-----------------------------------------------------------------------------------------"
        puts "Removing temporary files"
        puts "-----------------------------------------------------------------------------------------"
        run "rm #{shared_path}/tmp/#{stage}-#{remote_settings["database"]}-dump.sql"
        run_locally("rm tmp/#{stage}-#{remote_settings["database"]}-dump.sql")
        run_locally("rm tmp/#{stage}-database.yml")
      end

      desc "Download remote (system) assets to local machine"
      task :remote_assets do
        puts "-----------------------------------------------------------------------------------------"
        puts "Importing assets from #{domain} to local machine"
        puts "-----------------------------------------------------------------------------------------"
        system "rsync --recursive --times --rsh='ssh -p#{port}' --delete --compress --human-readable --progress #{user}@#{domain}:#{shared_path}/system/ public/system/"
      end
    end

    namespace :export do
      desc "Dump local database and export to remote"
      task :local_database do
        if enable_local_db_export

          # Confirm that we really want to override the database
          puts "-----------------------------------------------------------------------------------------"
          puts "Do you really want to override #{stage} database with your local version?"
          puts "-----------------------------------------------------------------------------------------"
          set :continue, Proc.new { Capistrano::CLI.ui.ask(' continue (y/n): ') }
          abort "Export to #{stage} was stopped" unless continue == 'y'

          # If stage is production - double check that we want to do this
          if "#{stage}" == 'production'
            puts "-----------------------------------------------------------------------------------------"
            puts "WARNING: You are overriding the PRODUCTION database, are you COMPLETELY sure?"
            puts "-----------------------------------------------------------------------------------------"
            set :continue, Proc.new { Capistrano::CLI.ui.ask('continue (y/n): ') }
            abort "Export to production was stopped" unless continue == 'y'
          end
        
          puts "-----------------------------------------------------------------------------------------"
          puts "Exporting database from local machine to #{domain}"
          puts "-----------------------------------------------------------------------------------------"
        
          get("#{shared_path}/config/database.yml", "tmp/#{stage}-database.yml")
        
          remote_settings = YAML::load_file("tmp/#{stage}-database.yml")["#{rails_env}"]
          local_settings = YAML::load_file("config/database.yml")["development"]

          # Dump local database
          puts "-----------------------------------------------------------------------------------------"
          puts "Dumping local database"
          puts "-----------------------------------------------------------------------------------------"
          run_locally("mysqldump -u#{local_settings['username']} #{"-p#{local_settings['password']}" if local_settings['password']} #{"-h#{local_settings['host']}" if local_settings['host']} #{local_settings['database']} > tmp/local-#{local_settings['database']}-dump.sql")

          # Rsync to remote
          puts "-----------------------------------------------------------------------------------------"
          puts "Rsyncing database from local to #{domain}"
          puts "-----------------------------------------------------------------------------------------"
          run_locally("rsync --times --rsh='ssh -p#{port}' --compress --human-readable --progress tmp/local-#{local_settings["database"]}-dump.sql #{user}@#{domain}:#{shared_path}/tmp/local-#{local_settings["database"]}-dump.sql")

          # Update database on remote
          puts "-----------------------------------------------------------------------------------------"
          puts "Updating database on #{domain}"
          puts "-----------------------------------------------------------------------------------------"
          run "mysql -u#{remote_settings['username']} #{"-p#{remote_settings['password']}" if remote_settings['password']} #{"-h#{remote_settings['host']}" if remote_settings['host']} #{remote_settings["database"]} < #{shared_path}/tmp/local-#{local_settings["database"]}-dump.sql"
      
          # Remove temporary files
          puts "-----------------------------------------------------------------------------------------"
          puts "Removing temporary files"
          puts "-----------------------------------------------------------------------------------------"
          run_locally("rm tmp/local-#{local_settings["database"]}-dump.sql")
          run_locally("rm tmp/#{stage}-database.yml")
          run "rm #{shared_path}/tmp/local-#{local_settings["database"]}-dump.sql"  
        else
          puts "-----------------------------------------------------------------------------------------"
          puts "NOTE: exporting your local database to #{stage} is disabled"
          puts "-----------------------------------------------------------------------------------------"
        end
      end

      desc "Downloads remote (system) assets to the local development machine"
      task :local_assets do
        if enable_local_asset_export
          # Confirm that we really want to upload local assets
          puts "-----------------------------------------------------------------------------------------"
          puts "Do you really want to upload local assets to #{stage} at #{domain}?"
          puts "-----------------------------------------------------------------------------------------"
          set :continue, Proc.new { Capistrano::CLI.ui.ask(' continue (y/n): ') }
          abort "Export to #{stage} was stopped" unless continue == 'y'
        
          # If stage is production - double check that we want to do this
          if "#{stage}" == 'production'
            puts "-----------------------------------------------------------------------------------------"
            puts "WARNING: You are overriding the PRODUCTION assets, are you COMPLETELY sure?"
            puts "-----------------------------------------------------------------------------------------"
            set :continue, Proc.new { Capistrano::CLI.ui.ask('continue (y/n): ') }
            abort "Export to production was stopped" unless continue == 'y'
          end

          puts "-----------------------------------------------------------------------------------------"
          puts "Exporting assets from local machine to #{domain}"
          puts "-----------------------------------------------------------------------------------------" 
          system "rsync --recursive --times --rsh='ssh -p#{port}' --delete --compress --human-readable --progress public/system/ #{user}@#{domain}:#{shared_path}/system/"
        else
          puts "-----------------------------------------------------------------------------------------"
          puts "NOTE: exporting your local assets to #{stage} is disabled"
          puts "-----------------------------------------------------------------------------------------"
        end
      end
    end

    namespace :unicorn do
      set(:unicorn_conf) { "#{deploy_to}/#{shared_dir}/config/unicorn.rb" }
      set(:unicorn_pid) { "#{deploy_to}/#{shared_dir}/pids/unicorn.pid" }

      task :restart do
        puts "-----------------------------------------------------------------------------------------"
        puts "Restarting unicorn"
        puts "-----------------------------------------------------------------------------------------"
        run "if [ -f #{unicorn_pid} ] && [ -e /proc/$(cat #{unicorn_pid}) ]; then kill -USR2 `cat #{unicorn_pid}`; else cd #{deploy_to}/current && bundle exec unicorn -c #{unicorn_conf} -E #{rails_env} -D; fi"
      end
      task :start do
        puts "-----------------------------------------------------------------------------------------"
        puts "Starting unicorn"
        puts "-----------------------------------------------------------------------------------------"
        run "cd #{deploy_to}/current && bundle exec unicorn -c #{unicorn_conf} -E #{rails_env} -D"
      end
      task :stop do
        puts "-----------------------------------------------------------------------------------------"
        puts "Stopping unicorn"
        puts "-----------------------------------------------------------------------------------------"
        run "if [ -f #{unicorn_pid} ] && [ -e /proc/$(cat #{unicorn_pid}) ]; then kill -QUIT `cat #{unicorn_pid}`; fi"
      end
    end
  end
end
