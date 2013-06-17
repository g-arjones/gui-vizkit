
module Vizkit
    class ContextMenu
        # Simple context menu to choose from a list of elements.
        # Elements have to be strings.
        # 
        # TODO use this method as generalization in all following special cases. 
        def self.basic(elements, parent, pos)
            Kernel.raise "No array submitted." unless elements.respond_to? "each"
            
            menu = Qt::Menu.new(parent)
            
            elements.each do |e|
                Kernel.raise "No conversion to a string from: #{e}" unless e.respond_to? "to_s"
                menu.add_action(Qt::Action.new(e.to_s, parent))
            end
            action = menu.exec(parent.viewport.map_to_global(pos))
            action.text if action
        end
        
        def self.widget_for(type_name,parent,pos)
            menu = Qt::Menu.new(parent)

            # Determine applicable widgets for the output port
            widgets = Vizkit.default_loader.find_all_plugin_names(:argument=>type_name, :callback_type => :display,:flags => {:deprecated => false})
            widgets.uniq!
            widgets.each do |w|
                menu.add_action(Qt::Action.new(w, parent))
            end
            # Display context menu at cursor position.
            action = menu.exec(parent.viewport.map_to_global(pos))
            action.text if action
        end

        def self.config_name_service(name_service,parent,pos)
            menu = Qt::Menu.new(parent)
            menu.add_action(Qt::Action.new("set ip", parent))

            # Display context menu at cursor position.
            action = menu.exec(parent.viewport.map_to_global(pos))
            action.text if action
        end

        def self.task_state(task,parent,pos)
            return if !task.respond_to? :model
            menu = Qt::Menu.new(parent)

            #add some helpers
            menu.add_action(Qt::Action.new("Load Configuration", parent))
            #there will be no task model if the Task is not reachable 
            begin
                if Orocos.conf.find_task_configuration_object(task)
                    menu.add_action(Qt::Action.new("Reapply Configuration", parent)) 
                end
            rescue ArgumentError
            end
            menu.add_action(Qt::Action.new("Save Configuration", parent))
            menu.addSeparator

            if task.current_state == :PRE_OPERATIONAL
                menu.add_action(Qt::Action.new("Configure Task", parent))
            elsif task.error?
                menu.add_action(Qt::Action.new("Reset Exception", parent))
            elsif task.running?
                menu.add_action(Qt::Action.new("Stop Task", parent))
                menu.add_action(Qt::Action.new("Reconfigure Task", parent))
            elsif task.ready?
                menu.add_action(Qt::Action.new("Cleanup Task", parent))
                menu.add_action(Qt::Action.new("Start Task", parent))
            end

            #check if there are widgets for the task 
            if task.model
                menu.addSeparator
                Vizkit.default_loader.find_all_plugin_names(:argument => task,:callback_type => :control,:flags => {:deprecated => false}).each do |w|
                    menu.add_action(Qt::Action.new(w, parent))
                end
            end

            # Display context menu at cursor position.
            action = menu.exec(parent.viewport.map_to_global(pos))
            if action
                begin
                    if action.text == "Start Task"
                        task.start
                    elsif action.text == "Configure Task"
                        task.configure
                    elsif action.text == "Stop Task"
                        task.stop
                    elsif action.text == "Reset Exception"
                        task.reset_exception
                    elsif action.text == "Cleanup Task"
                        task.cleanup
                    elsif action.text == "Reconfigure Task"
                        task.stop
                        task.cleanup
                        task.configure
                        task.start
                    elsif action.text == "Load Configuration"
                        file_name = Qt::FileDialog::getOpenFileName(nil,"Load Config",File.expand_path("."),"Config Files (*.yml)")
                        task.apply_conf_file(file_name) if file_name
                    elsif action.text == "Apply Configuration"
                        task.apply_conf
                    elsif action.text == "Save Configuration"
                        file_name = Qt::FileDialog::getSaveFileName(nil,"Save Config",File.expand_path("."),"Config Files (*.yml)")
                        #delete the file if it already exists (the dialog is asking the use)
                        #TODO add code to merge the configuration with an existing file 
                        if file_name
                            File.delete file_name if File.exist? file_name
                            task.save_conf(file_name) if file_name
                        end
                    elsif
                        Vizkit.control task.__task,:widget => action.text
                    end
                rescue RuntimeError => e 
                    Qt::MessageBox::warning(nil,"Failed",e.message)
                end
            end
        rescue Orocos::NotFound
            # the task is not reachable 
        end

        # displays the menu for a given Async::Log::TaskContext
        def self.log_task(task,parent,pos)
            menu = Qt::Menu.new(parent)
            action = Qt::Action.new("Export to CORBA", parent)
            action.checkable = true
            if task.ruby_task_context?
                action.checked = true
            else
                action.connect SIGNAL("triggered(bool)") do |val|
                    begin
                        task.to_ruby_task_context
                    rescue Exception => e
                        Qt::MessageBox::warning(nil,"Export to CORBA",e.to_s)
                    end
                end
            end
            menu.add_action(action)
            menu.exec(parent.viewport.map_to_global(pos))
        end

        def self.control_widget_for(type_name,parent,pos)
            menu = Qt::Menu.new(parent)
            Vizkit.default_loader.find_all_plugin_names(:argument => type_name,:callback_type => :control,:flags => {:deprecated => false}).each do |w|
                menu.add_action(Qt::Action.new(w, parent))
            end
            # Display context menu at cursor position.
            action = menu.exec(parent.viewport.map_to_global(pos))
            action.text if action
        end
    end
end
