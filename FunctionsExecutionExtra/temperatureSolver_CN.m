% Solves temperatures within model.
% Script File: temperatureSolverInitialisation.m
% Author: Stephen Blowers  -  S.Blowers@ed.ac.uk
% Date Modified: 08/02/2017
% Description: Solves temperatures using initialised options and
% parameters. Runs the script temperatureSolverSetUp or
% temperatureSolverSetUp_Pennes depending on what options are chosen to
% create a sparse matrix that is then solved as a linear set of equations.



disp('%%%%%%% Solving Temperatures %%%%%%%%%%%%%%%%%%%%%%') % Display.

%%%%%% Using Graetz Number %%%%%%%%%%%%%%%%%%%%%%

if Option_GraetzNumber && ~Option_PennesOnly
    Gz1 = Rho_b*Cp_b*(max(abs(FdotArt),[],2)/Rho_b./Aavg1).*Davg1.^2/Kc_b./L1;
    Gz2 = Rho_b*Cp_b*(min(abs(FdotVein),[],2)/Rho_b./Aavg2).*Davg2.^2/Kc_b./L2;
    Nu1 = Nu+0.155*exp(1.58*log10(Gz1));
    Nu2 = Nu+0.155*exp(1.58*log10(Gz2));
    
    Nu1(Nu1>20) = 20;
    Nu2(Nu2>20) = 20; % Capped as the equation is only valid for Gz<1000
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%% Vessel Inter-Domain Heat Transfer Terms %%
if ~Option_PennesOnly
    Beta1 = zeros(size(Vessel1,1),1);
    for n = 2:size(Vessel1,1)
        if size(Vessel2Volume1{n},1)~=0
            if Option_GraetzNumber
                Beta1(n) = (Nu1(n)*Kc_b./Davg1(n)).*AL1(n) / size(Vessel2Volume1{n},1);
            else
                Beta1(n) = (Nu*Kc_b./Davg1(n)).*AL1(n) / size(Vessel2Volume1{n},1);
            end
        end
    end
    % Setting up inter-domain heat transfer terms for each arterial line
    % segment.
    
    Beta2 = zeros(size(Vessel2,1),1);
    for n = 2:size(Vessel2,1)
        if size(Vessel2Volume2{n},1)~=0
            if Option_GraetzNumber
                Beta2(n) = (Nu2(n)*Kc_b./Davg2(n)).*AL2(n) / size(Vessel2Volume2{n},1);
            else
                Beta2(n) = (Nu*Kc_b./Davg2(n)).*AL2(n) / size(Vessel2Volume2{n},1);
            end
        end
    end
    % Setting up inter-domain heat transfer terms for each venous line
    % segment.
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%% Fixing LimitedCoolingHeight if Needed %%%%
if Option_LimitedCooling
    if strcmp(Option_DomainCoarsening, 'two') || strcmp(Option_DomainCoarsening, 'six')
        LimitedCoolingHeight = round(LimitedCoolingHeight/2);
    end
    if strcmp(Option_DomainCoarsening, 'three') || strcmp(Option_DomainCoarsening, 'six')
        LimitedCoolingHeight = round(LimitedCoolingHeight/3);
    end
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%% Compiling Interactions %%%%%%%%%%%%%%%%%%%
if Option_PennesOnly
    temperatureSolverSetUp_PennesOnly
else
    temperatureSolverSetUp_CN
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


    if TransientLoadTemp % Load previous temperature results for initial conditions
        load(LoadPreviousFilename,'Tt_Save','T_Art_Save','T_Vein_Save')
        if  Beta23 == Inf
            T_NOld = [Tt_Save(DomTot);T_Art_Save;T_Vein_Save];
        else
            T_NOld = [Tt_Save(DomTot);Tt_Save(DomTot);T_Art_Save;T_Vein_Save];
        end
    else
        T_NOld = TransientInitialTemp*ones(size(D));
    end
    
    if ~Option_PennesOnly
        T_NOld_Time(NumDomRows + InletPoints) = InletTemp;
    end
    NoTimesteps = ceil(TotalTime/Timestep);
    TotalTime = NoTimesteps*Timestep;
    
    T_TransientStore = zeros(size(D,1),round(NoTimesteps*Timestep/SaveTime)+1);
    T_TransientStore(:,1) = T_NOld;
    
    T_TransientAdjust = zeros(size(D));
    
    if Option_PennesOnly
        T_TransientAdjust(1:NumDomTot) = Vol*Rho(RowConvert).*Cp(RowConvert)/Timestep;
    else
        
        T_TransientAdjust(1:NumDomTot) = Vol*(1-Porosity(RowConvert)).*Rho(RowConvert).*Cp(RowConvert)/Timestep;
        
        if Beta23 == Inf
            T_TransientAdjust(1:NumDomTot) = T_TransientAdjust(1:NumDomTot) +...
                Vol*Porosity(RowConvert)*Rho_b*Cp_b/Timestep;
        else
            T_TransientAdjust(NumDomTot+1:NumDomRows) = Vol*Porosity(RowConvert)*Rho_b.*Cp_b/Timestep;
        end
        
        T_TransientAdjust(NumDomRows+1:NumDomRows+VesselRow) = Vol1*Rho_b*Cp_b/Timestep;
        T_TransientAdjust(NumDomRows+VesselRow+1:end) = Vol2*Rho_b*Cp_b/Timestep;
        
        T_TransientAdjust(NumDomRows + InletPoints) = 0;
        
    end
    
    if Option_VaryingInlet, VaryingInletCheck = true; end
    
    D_Backup = D;
    
    for TimeNo = 1:NoTimesteps
        
        disp(['Timestep: ' num2str(TimeNo) '/' num2str(NoTimesteps)])
        %         D = D - T_TransientAdjust.*T_NOld;
        T_TransientAdjust2 = T_Solve*T_NOld;
        T_TransientAdjust2(NumDomRows + InletPoints) = 0;
        D = D_Backup - 2*(T_TransientAdjust.*T_NOld) - T_TransientAdjust2;
        
        disp(['Solving Matrix Inversion size: ' num2str(size(T_Solve,1)) ' by ' num2str(size(T_Solve,2))]) % Display.
        tic % Start timing.
        
        T_N = T_Solve\D; % Solve the linear system.
        
        toc % Finish timing.
        disp('Matrix Inversion Completed') % Display.
        
        %         D = D + T_TransientAdjust.*T_NOld;
        T_NOld = T_N;
        
        if rem(TimeNo*Timestep,SaveTime) == 0
            T_TransientStore(:,round(TimeNo*Timestep/SaveTime+1)) = T_N;
        end
        
        if Option_VaryingInlet && VaryingInletCheck && (TimeNo*Timestep > TimeChange)
            disp('Changing Inlet Conditions')
            BloodTemp = BloodTempNew;
            InletTemp = InletTempNew;
            if Option_PennesOnly
                temperatureSolverSetUp_PennesOnly
            else
                temperatureSolverSetUp_CN
            end
            VaryingInletCheck = false;
            
            D_Backup = D;
        end
        
    end


%%%%%% Reshaping Resutls from Solver %%%%%%%%%%%%
if Option_PennesOnly
    Tt = zeros(size(DomTot));
    Tt(RowConvert) = T_N(1:NumDomTot);
    
    Tt(~DomTot) = NaN;
    % Setting all values outside of the domain to NaN. This facilitates
    % visualisation of data with 'planecut'.
else
    Tt = zeros(size(DomTot));
    Tt(RowConvert) = T_N(1:NumDomTot);
    
    if Beta23 == Inf
        Tb = Tt;
    else
        Tb = T_N(NumDomTot+1:NumDomRows);
    end
    
    T_Art = T_N(NumDomRows+1:NumDomRows+VesselRow);
    T_Vein = T_N(NumDomRows+1+VesselRow:end);
    
    Tt(~DomTot) = NaN;
    Tb(~DomTot) = NaN;
    % Setting all values outside of the domain to NaN. This facilitates
    % visualisation of data with 'planecut'.
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


disp('%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%') % Display.