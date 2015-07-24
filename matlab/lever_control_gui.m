function lever_control_gui
    global gui;
    if(~isempty(gui))
        return;
    end
    addpath(fileparts(mfilename('fullpath')))
    createInterface();
    
    function parameters = getInitialParameters()
        parameters.mouse.name='AM0000';
        
        parameters.behavior.iti=4;
        parameters.behavior.response=10;
        parameters.behavior.nfb_delay=0.7;
        parameters.behavior.nfb_window=1;
        parameters.behavior.water_hit=0.1;
        parameters.behavior.water_nfb_on=0;
        parameters.behavior.water_nfb_off=0;
        parameters.behavior.motor_steps=uint8(5);
        
        if(isunix())
            parameters.serial.control_port = '/dev/tty.usbmodem1411';
            parameters.serial.data_port = '/dev/tty.usbserial';
        else
            parameters.serial.control_port = 'COM4';
            parameters.serial.data_port = 'COM5';
        end
        parameters.serial.control_baud_rate = '115200';
        parameters.serial.data_baud_rate = '230400';
    end
    function createInterface(  )
        % Create the user interface for the application and return a
        % structure of handles for global use.
        gui = struct();
        % Open a window and add some menus
        gui.Window = figure( ...
            'Name', 'Lever Control Window', ...
            'NumberTitle', 'off', ...
            'MenuBar', 'none', ...
            'Toolbar', 'none', ...
            'HandleVisibility', 'on',...
            'WindowStyle', 'docked',...
            'CloseRequestFcn',@my_closereq);
        pause(0.1); % somehow layout got broken without this.
        
        % Set default panel color
        uiextras.set( gui.Window, 'DefaultBoxPanelTitleColor', [0.7 1.0 0.7] );
        
        % Arrange the main interface
        mainLayout = uiextras.HBox( 'Parent', gui.Window, 'Spacing', 3 );
        
        propertiesLayout = uiextras.VBox( 'Parent', mainLayout, 'Spacing', 3 );
        
        % + Create the panels
        parametersPanel = uiextras.BoxPanel( ...
            'Parent', propertiesLayout, ...
            'Title', 'Parameters','BorderType','none');
        buttonPanel = uiextras.BoxPanel( ...
            'Parent', propertiesLayout, ...
            'Title', 'Control','BorderType','none');
        
        mouseButtonGrid = uiextras.Grid( ...
            'Parent', buttonPanel,'Spacing', 3,'Padding', 3);
        
        behaviorButtonGrid = uiextras.Grid( ...
            'Parent', propertiesLayout,'Spacing', 3,'Padding', 3);
        
        serialButtonGrid = uiextras.Grid( ...
            'Parent', propertiesLayout, 'Spacing', 3, 'Padding', 3);
        
        gui.ViewPanel = uiextras.BoxPanel( ...
            'Parent', mainLayout, ...
            'Title', 'Controls', 'BorderType','none');

        % + Adjust the main layout
        set( mainLayout, 'Sizes', [200,-1] );
        set( propertiesLayout, 'Sizes', [-1, 70, 130, 30] );
        
        
        % + Create the controls
        ParametersPanel = uipanel('Parent',parametersPanel,'BorderType','none');
        gui.propertiesGUI = propertiesGUI(ParametersPanel, getInitialParameters());
        setappdata(gui.Window, 'propUpdateCallback',@propUpdateCallback);
        
        gui.btLoad = uicontrol('Parent',mouseButtonGrid,'String','Load','Callback',@bt_Callback);
        gui.btUpdate = uicontrol('Parent',mouseButtonGrid,'String','Update','Callback',@bt_Callback);
        gui.btLoadLatest = uicontrol('Parent',mouseButtonGrid,'String','Load Latest','Callback',@bt_Callback);
        gui.btSaveAs = uicontrol('Parent',mouseButtonGrid,'String','Save as','Callback',@bt_Callback);
        
        gui.behavior.btStart = uicontrol('Parent',behaviorButtonGrid,'Enable','off','String','Start','Callback',@bt_Callback);
        gui.behavior.btPause = uicontrol('Parent',behaviorButtonGrid,'Enable','off','String','Pause','Callback',@bt_Callback);
        gui.behavior.btWater100 = uicontrol('Parent',behaviorButtonGrid,'Enable','off','String','Water 0.1','Callback',@bt_Callback);
        gui.behavior.btWaterOn = uicontrol('Parent',behaviorButtonGrid,'Enable','off','String','Water On','Callback',@bt_Callback);
        gui.behavior.btLeverOff = uicontrol('Parent',behaviorButtonGrid,'Enable','off','String', 'Lever off','Callback',@bt_Callback);
        
        gui.behavior.btStop = uicontrol('Parent',behaviorButtonGrid,'Enable','off','String','Stop','Callback',@bt_Callback);
        gui.behavior.btResume = uicontrol('Parent',behaviorButtonGrid,'Enable','off','String','Resume','Callback',@bt_Callback);
        gui.behavior.btWater50 = uicontrol('Parent',behaviorButtonGrid,'Enable','off','String','Water 0.05','Callback',@bt_Callback);
        gui.behavior.btWaterOff = uicontrol('Parent',behaviorButtonGrid,'Enable','off','String','Water Off','Callback',@bt_Callback);
        gui.behavior.btLeverReinit = uicontrol('Parent',behaviorButtonGrid,'Enable','off','String','Lever reinit','Callback',@bt_Callback);
        
        gui.serial.btConnect = uicontrol('Parent',serialButtonGrid,'String','Connect','Callback',@bt_Callback);
        gui.serial.btDisconnect = uicontrol('Parent',serialButtonGrid,'Enable','off','String','Disconnect','Callback',@bt_Callback);
        gui.connected=false;
        
        gui.trial_history=[];
        gui.last_set_cmd='';
        
        set(mouseButtonGrid,'ColumnSizes',[-1 -1]);
        set(behaviorButtonGrid,'ColumnSizes',[-1 -1]); 
        set(serialButtonGrid,'ColumnSizes',[-1 -1]);
        
        
        lockDuringRun(false)
        enableButtonsAfterConnect(false)
        
        % + Create the view
        p = gui.ViewPanel;
        gui.ViewAxes = axes( 'Parent', p );
        
    end % createInterface
    function propUpdateCallback(propName,propValue) %propName, propValue
        disp([propName ': ' propValue]);
        if(gui.connected)
            updateParameters();
        end
    end
    function pathname = defaultPathName()
        pathname=fullfile(fileparts(fileparts(mfilename('fullpath'))),'data');
        if(~exist(pathname,'dir'))
            mkdir(pathname);
        end
    end
    function filename = defaultParamsFileName()
        [~,params] = propertiesGUI(gui.propertiesGUI);
        filename=fullfile(defaultPathName(),[params.mouse.name '-' datestr(now,'yyyy_mm_dd-HH_MM_SS') '.mat']);
    end
    function filename = defaultDataFileName()
        [~,params] = propertiesGUI(gui.propertiesGUI);
        filename=fullfile(defaultPathName(),[params.mouse.name '-' datestr(now,'yyyy_mm_dd-HH_MM_SS') '.dat']);
    end
    function updateParameters()
        [~,params] = propertiesGUI(gui.propertiesGUI);
        cmd=sprintf('set %d %d %d %d %d %d %d %d'...
        ,1000*params.behavior.iti...
        ,1000*params.behavior.response...
        ,1000*params.behavior.nfb_delay...
        ,1000*params.behavior.nfb_window...
        ,1000*params.behavior.water_hit...
        ,1000*params.behavior.water_nfb_on...
        ,1000*params.behavior.water_nfb_off...
        ,params.behavior.motor_steps);
        if(~strcmp(gui.last_set_cmd,cmd))
            fprintf(gui.serial_control,cmd);
            propertiesGUI(gui.propertiesGUI, 'save', defaultParamsFileName(), '');
        end
        gui.last_set_cmd=cmd;
    end
    function bt_Callback(h,~)
        switch(h)
            case gui.btLoad
                [filename, pathname] = uigetfile('*.mat','Select setting file',defaultPathName());
                if(~isequal(filename,0))
                    propertiesGUI(gui.propertiesGUI, 'load', fullfile(filename,pathname), '');
                end
            case gui.btUpdate
                assert(gui.connected)
                updateParameters()
            case gui.btSaveAs
                [filename, pathname] = uiputfile('*.mat','Save as',defaultParamsFileName());
                if(~isequal(filename,0))
                    propertiesGUI(gui.propertiesGUI, 'save', fullfile(pathname,filename), '');
                end
            case gui.btLoadLatest
                warning('NOT IMPLEMENTED');
            
            case gui.behavior.btStart
                [~,params] = propertiesGUI(gui.propertiesGUI);
                cmd=sprintf('python ../python/bgPID.py python ../python/serialToFile.py %s -s %s -b %s',...
                    defaultDataFileName(),...
                    params.serial.data_port,params.serial.data_baud_rate);
                [~,gui.pid]=system(cmd);
                updateParameters();
                fprintf(gui.serial_control,'start');
                lockDuringRun(true);
                gui.trial_history=[];
            case gui.behavior.btStop
                fprintf(gui.serial_control,'pause');
                
                cmd=sprintf('python ../python/sendSIGINT.py %s',gui.pid);
                system(cmd);
                
                lockDuringRun(false);
            case gui.behavior.btResume
                fprintf(gui.serial_control,'resume');
            case gui.behavior.btPause
                fprintf(gui.serial_control,'pause');
            case gui.behavior.btWater100
                fprintf(gui.serial_control,'water 100');
            case gui.behavior.btWater50
                fprintf(gui.serial_control,'water 50');
            case gui.behavior.btWaterOn
                fprintf(gui.serial_control,'water on');
            case gui.behavior.btWaterOff
                fprintf(gui.serial_control,'water off');
            case gui.behavior.btLeverOff
                fprintf(gui.serial_control,'lever off');
            case gui.behavior.btLeverReinit
                fprintf(gui.serial_control,'lever reinit');
            case gui.serial.btConnect
                closeSerials();
                try
                    [~,params] = propertiesGUI(gui.propertiesGUI);
                    
                    gui.serial_control=serial(params.serial.control_port,...
                        'BaudRate',str2double(params.serial.control_baud_rate),...
                        'Terminator','LF','DataTerminalReady','off','RequestToSend','off');
                    fopen(gui.serial_control);
                    gui.serial_control.BytesAvailableFcn = @serialControlCallback;
                    pause(1);
                    fprintf(gui.serial_control,'');
                    fprintf(gui.serial_control,'pause');
                catch e
                    closeSerials();
                    rethrow(e);
                end
                enableButtonsAfterConnect(true);
            case gui.serial.btDisconnect
                closeSerials()
                enableButtonsAfterConnect(false);
            otherwise
                warning('Unknown button');
        end
    end
    function closeSerials()
        if(isfield(gui,'serial_control')&&~isempty(gui.serial_control))
            try
                fclose(gui.serial_control);
                delete(gui.serial_control);
            catch
            end
        end
        if(isfield(gui,'serial_data')&&~isempty(gui.serial_data))
            try
                fclose(gui.serial_data);
                delete(gui.serial_data);
            catch
            end
        end
    end
    function lockDuringRun(toLock)
        [~,~, propsList] = propertiesGUI(gui.propertiesGUI);
        propsArray=propsList.toArray();
        for i=[1 3]
            propCategory=propsArray(i);
            propsListSub=get(propCategory,'Children');
            propsArraySub=propsListSub.toArray();
            for j=1:length(propsArraySub)
                propName=propsArraySub(j);
                set(propName,'Editable',~toLock);
            end
        end
        if(toLock)
            set(gui.serial.btDisconnect,'Enable','off');
            set(gui.behavior.btStart,'Enable','off');
            set(gui.behavior.btStop,'Enable','on');
            set(gui.behavior.btPause,'Enable','on');
            set(gui.behavior.btResume,'Enable','on');
            set(gui.btUpdate,'Enable','on');
        else
            set(gui.serial.btDisconnect,'Enable','on');
            set(gui.behavior.btStart,'Enable','on');
            set(gui.behavior.btStop,'Enable','off');
            set(gui.behavior.btPause,'Enable','off');
            set(gui.behavior.btResume,'Enable','off');
            set(gui.btUpdate,'Enable','off');
        end
    end
    function enableButtonsAfterConnect(toEnable)
        fields=fieldnames(gui.behavior);
        for i=1:length(fields)
            if(toEnable)
                set(gui.behavior.(fields{i}),'Enable','on');
            else
                set(gui.behavior.(fields{i}),'Enable','off');
            end
        end
        if(toEnable)
            set(gui.serial.btDisconnect,'Enable','on');
            set(gui.serial.btConnect,'Enable','off');
            set(gui.behavior.btStop,'Enable','off');
            set(gui.behavior.btPause,'Enable','off');
            set(gui.behavior.btResume,'Enable','off');
        else
            set(gui.serial.btDisconnect,'Enable','off');
            set(gui.serial.btConnect,'Enable','on');
        end
        gui.connected=toEnable;
    end
    function serialControlCallback(h,e)
        try
            txt=fscanf(gui.serial_control);
            if(isempty(txt)), return, end
            switch(txt(1))
                case '>'
                    fprintf('%s',txt);
                case '*'
                    trial=regexp(txt(2:end),'(?<trial_num>\d+)\s*(?<state>\w*)','names','once');
                    if(isempty(trial)),return,end
                    if(~isempty(gui.trial_history))
                        gui.trial_history(end+1)=trial;
                    else
                        gui.trial_history=trial;
                    end
                    updatePlot();
                case 'S'
                    %fprintf('%s',txt);
                otherwise
                    fprintf('error: %s',txt);
            end
        catch e
            disp(e);
        end
    end
    function updatePlot()
        [s,~,I]=unique({gui.trial_history.state});
        for i=1:length(s)
            fprintf('\t%s: %d',s{i},sum(I==i));
        end
        fprintf('\n');
    end
    function copyToServer()
        
    end
    function my_closereq(~,~)
    % Close request function 
    % to display a question dialog box 
        closeSerials();
        copyToServer();
        delete(gcf)
        gui=[];
        selection = questdlg('Close?',...
           'Close Request Function',...
           'Yes','No','Yes'); 
        switch selection, 
           case 'Yes',
              delete(gcf)
           case 'No'
           return 
        end
    end
end