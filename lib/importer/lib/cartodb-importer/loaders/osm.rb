module CartoDB
  module Import
    class SHP < CartoDB::Import::Loader
      
      register_loader :bz2
      register_loader :osm

      def process!
        @data_import = DataImport.find(:id=>@data_import_id)

        log "processing osm"
        osm2pgsql_bin_path = `which osm2pgsql`.strip

        host = @db_configuration[:host] ? "-h #{@db_configuration[:host]}" : ""
        port = @db_configuration[:port] ? "-p #{@db_configuration[:port]}" : ""
        
        # TODO
        # Create either a dynamic cache size based on user account type or pick a wiser number
        # for everybody
        allowed_cache_size = 24000
        random_table_prefix = "importing_#{Time.now.to_i}_#{@suggested_name}"


        full_osm_command = "#{shp2pgsql_bin_path} -s #{shp_args_command[0]} -D -i -g the_geom -W #{shp_args_command[1]} \"#{shp_args_command[2]}\" #{shp_args_command[3].strip} | #{@psql_bin_path} #{host} #{port} -U #{@db_configuration[:username]} -w -d #{@db_configuration[:database]}"
        
        full_osm_command = "#{osm2pgsql_bin_path} -H #{host} -P #{port} -U #{@db_configuration[:username]} -d #{@db_configuration[:database]} -u -G -I -C #{allowed_cache_size} -p #{random_table_prefix} #{@path}"
        
        log "Running osm2pgsql: #{full_osm_command}"
        @data_import.log_update(full_osm_command)
        
        stdin,  stdout, stderr = Open3.popen3(full_osm_command) 
  
        #unless (err = stderr.read).empty?
        if $?.exitstatus != 0  
          @data_import.set_error_code(3005)
          @data_import.log_error(stderr)
          @data_import.log_error("ERROR: failed to import #{@path}")
          raise "ERROR: failed to import #{@path}"
        end
        
        unless (reg = stdout.read).empty?
          @runlog.stdout << reg
        end
        
        
        begin
          @db_connection.run("ALTER TABLE \"#{random_table_prefix}_point\" RENAME TO #{@suggested_name}_point")
          @table_created = true
        rescue Exception => msg  
          @runlog.err << msg
          @data_import.set_error_code(5000)
          @data_import.log_error(msg)
          @data_import.log_error("ERROR: unable to rename \"#{random_table_name}\" to \"#{@suggested_name}\"")
        end  

        @entries.each{ |e| FileUtils.rm_rf(e) } if @entries.any?
        rows_imported = @db_connection["SELECT count(*) as count from #{@suggested_name}_point"].first[:count]
        @import_from_file.unlink

        payload = OpenStruct.new({
                                :name => "#{@suggested_name}_point", 
                                :rows_imported => rows_imported,
                                :import_type => @import_type,
                                :log => @runlog
                              })
 
        # construct return variables
        [to_import_hash, payload]        
      end  
    end
  end    
end