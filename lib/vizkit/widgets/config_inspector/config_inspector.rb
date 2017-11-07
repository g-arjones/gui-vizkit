#!/usr/bin/env ruby

require 'vizkit'
require 'vizkit/tree_view'
require 'syskit/shell_interface'

class ConfigInspectorItem < Vizkit::VizkitItem
    attr_reader :current_model, :editing_model
    def initialize(model)
        super()
        @current_model = deep_copy(model)
        @editing_model = deep_copy(model)
    end

    def deep_copy(model)
        Marshal.load(Marshal.dump(model))
    end

    def add_conf_item(label, accessor = nil)
        item1 = Vizkit::VizkitItem.new(label)
        item2 = RubyItem.new

        if !accessor.nil?
            item2.getter do
                @editing_model.method(accessor).call
            end

            item2.setter do |value|
                @editing_model.method("#{accessor}=".to_sym).call value
            end
        end

        appendRow([item1, item2])
        return item1, item2
    end

    def data(role = Qt::UserRole+1)
        if role == Qt::EditRole 
            Qt::Variant.from_ruby self
        else
            super
        end
    end

    def modified!(value = true, items = [],update_parent = false)
        super
        reject_changes unless value
        if column == 0
            i = index.sibling(row,1)
            if i.isValid
                item = i.model.itemFromIndex i
                item.modified!(value,items)
            end
        end
    end

    def reject_changes
        @editing_model = deep_copy(@current_model)
    end

    def accept_changes
        @current_model = deep_copy(@editing_model)
    end
end

class LoggingGroupsItem < ConfigInspectorItem
    def initialize(logging_groups, label = '')
        super(logging_groups)

        @groups_item1 = Hash.new
        @groups_item2 = Hash.new

        setText label
        update_groups(logging_groups)
    end

    def update_groups(groups)
        @current_model.keys.each do |key|
            if !groups.key? key
                group_row = @groups_item1[key].index.row
                @groups_item1[key].clear
                @groups_item2[key].clear
                @groups_item1.delete key
                @groups_item2.delete key
                removeRow(group_row)
            end
        end

        @current_model = deep_copy(groups)
        @editing_model = deep_copy(groups)

        @current_model.keys.each do |key|
            if !@groups_item1.key? key
                @groups_item1[key], @groups_item2[key] = add_conf_item(key)
                @groups_item2[key].getter do
                    @editing_model[key].enabled
                end
                @groups_item2[key].setter do |value|
                    @editing_model[key].enabled = value
                end
            end
        end
    end
end

class LoggingConfigurationItem < ConfigInspectorItem
    attr_reader :options
    def initialize(logging_configuration, options = Hash.new)
        super(logging_configuration)
        @options = options    
        setText 'Logging Configuration'

        @conf_logs_item1, @conf_logs_item2 = add_conf_item('Enable conf logs', 
                                                :conf_logs_enabled)
        @port_logs_item1, @port_logs_item2 = add_conf_item('Enable port logs', 
                                                :port_logs_enabled)

        @groups_item1 = LoggingGroupsItem.new(@current_model.groups, 'Enable group')
        @groups_item2 = Vizkit::VizkitItem.new("#{@current_model.groups.size} logging group(s)")
        appendRow([@groups_item1, @groups_item2])
    end

    def write
        if column == 1
            i = index.sibling(row, 0)
            return if !i.isValid
    
            item = i.model.itemFromIndex i
            item.accept_changes
        end
        modified!(false)        
    end

    def accept_changes
        super
        @groups_item1.accept_changes
        @current_model.groups = @groups_item1.current_model
    end

    def update_conf(new_model)
        @current_model = deep_copy(new_model)
        @editing_model = deep_copy(new_model)
        @groups_item1.update_groups(@current_model.groups)
        @groups_item2.setText "#{@current_model.groups.size} logging group(s)"
        model.layoutChanged
    end
end

class RubyItem < Vizkit::VizkitAccessorItem
    def initialize
        super(nil, :nil?)
        setEditable false
    end

    def setData(data,role = Qt::UserRole+1)
        return super if role != Qt::EditRole || data.isNull
        val = from_variant data, @getter.call
        return false if val.nil?
        return false unless val != @getter.call
        @setter.call val
        modified!
    end

    def setter(&block)
        @setter = block
        setEditable true
    end

    def getter(&block)
        @getter = block
    end
end

class ConfigInspector < Qt::Widget
    attr_reader :model, :treeView, :syskit
    def initialize(parent = nil, syskit)
        super(parent)
        main_layout = Qt::VBoxLayout.new(self)
        @treeView = Qt::TreeView.new

        Vizkit.setup_tree_view treeView
        @model = Vizkit::VizkitItemModel.new
        treeView.setModel @model
        main_layout.add_widget(treeView)
        treeView.setColumnWidth(0, 200)
        treeView.style_sheet = "QTreeView { background-color: rgb(255, 255, 219);
                                            alternate-background-color: rgb(255, 255, 174); }"

        @syskit = syskit
        @timer = Qt::Timer.new
        @timer.connect(SIGNAL('timeout()')) { refresh }
        @timer.start 1000

        update_model(Syskit::ShellInterface::LoggingConfiguration.new(false, false, Hash.new))
        refresh
    end

    def refresh
        if !syskit.client.nil?
            conf = syskit.client.call ['syskit'], :logging_conf
            update_model(conf)
            enabled true
        else
            enabled false
        end
    end

    def recursive_expand(item)
        treeView.expand(item.index)
        (0...item.rowCount).each do |i|
            recursive_expand(item.child(i))
        end
    end

    def enabled (toggle)
        @item1.enabled toggle
    end

    def update_model(conf)
        if @item1.nil?
            @item1 = LoggingConfigurationItem.new(conf, :accept => true)
            @item2 = LoggingConfigurationItem.new(conf)
            @item2.setEditable true
            @item2.setText ""
            @model.appendRow([@item1, @item2])
            recursive_expand(@item1)
        else
            return if @item1.modified?
            @item1.update_conf(conf)
        end
    end
end
