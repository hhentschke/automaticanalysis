% Based on Guillaume Flandin's spm_provenance.m and spm_results_nidm.m

classdef aa_provenance < handle
    properties
        version = '0.0.1'
        pp
        p
		isvalid = false
    end
    
    properties (Hidden, SetAccess = private)
        provlib
        aap
        studypath
        
        dep
        relations = {}
    end
    
    properties (SetAccess = private)
        IDs = {}
        isHumanReadable = true;
    end
    
    methods
        function obj = aa_provenance(aap)
            obj.aap = aap;
            obj.studypath = fullfile(obj.aap.acq_details.root,obj.aap.directory_conventions.analysisid);
            obj.dep = dep_read(fullfile(obj.studypath,'aap_prov.trp'));
            obj.provlib = which('spm_provenance'); % check availability
            if ~isempty(obj.provlib)
				obj.isvalid = true;
			
                % Initialise
                obj.pp = eval(basename(obj.provlib));
                obj.pp.add_namespace('nfo','http://www.semanticdesktop.org/ontologies/2007/03/22/nfo');
                obj.pp.add_namespace('aa','http://automaticanalysis.org/'); % TODO: place
                obj.pp.add_namespace('nidm','http://www.incf.org/ns/nidash/nidm#');
                obj.pp.add_namespace('spm','http://www.incf.org/ns/nidash/spm#');
                
                % agents
                % Parallel Computing
                obj.pp.agent('idPCP1',{...
                    'prov:type','aa:ParallelComputingProvider',...
                    'prov:label',obj.aap.options.wheretoprocess,...
                    });      
                
                % MATLAB
                obj.pp.agent('idMATLAB1',{...
                    'prov:type','prov:SoftwareAgent',...
                    'prov:label',{'MATLAB','xsd:string'},...
                    'aa:version',{version,'xsd:string'},...
                    'nfo:belongsToContainer',{matlabroot, 'nfo:Folder'},...                    
                    'aa:runs','idaa1',...
                    });
                
                % aa
                aagent = aa;
                obj.pp.agent('idaa',{...
                    'prov:type','aa:PipelineProcessor',...
                    'prov:label',aagent.Name,...
                    'nfo:belongsToContainer',{aagent.Path, 'nfo:Folder'},...                    
                    'aa:version',{aagent.Version,'xsd:string'},...
                    'aa:isTrackKeeping','1',...
                    'aa:hasParallelComputing','idPCP1',...
                    'aa:runs','idSPM1',...
                    'aa:runs','idFSL1',...
                    'aa:runs','idFreeSurfer1',...
                    });
                
                % SPM
                spmdir0 = fileparts(which('spm'));
                spmdir = obj.aap.directory_conventions.spmdir;
                rmpath(spmdir0); addpath(spmdir);
                [V,R] = spm('Ver');
                rmpath(spmdir); addpath(spmdir0);
                obj.pp.agent('idSPM1',{...
                    'prov:type','nidm:SPM',...
                    'prov:type','prov:SoftwareAgent',...
                    'prov:label',{'SPM','xsd:string'},...
                    'aa:version',{V,'xsd:string'},...
                    'spm:softwareRevision',{R,'xsd:string'},...
                    'nfo:belongsToContainer',{spmdir, 'nfo:Folder'},...                    
                    });

                % FSL
                fsldir = obj.aap.directory_conventions.fsldir;
                fslversion = importdata(fullfile(fsldir,'etc','fslversion'));
                obj.pp.agent('idFSL1',{...
                    'prov:type','prov:SoftwareAgent',...
                    'prov:label',{'FSL','xsd:string'},...
                    'aa:version',{fslversion{1},'xsd:string'},...
                    'nfo:belongsToContainer',{fsldir, 'nfo:Folder'},...                    
                    });
                
                % FreeSurfer
                fsdir = obj.aap.directory_conventions.freesurferdir;
                fsversion = importdata(fullfile(fsdir,'build-stamp.txt')); fsversion = textscan(fsversion{1},'%s','delimiter','-');
                obj.pp.agent('idFreeSurfer1',{...
                    'prov:type','prov:SoftwareAgent',...
                    'prov:label',{'FreeSurfer','xsd:string'},...
                    'aa:version',{fsversion{1}{end},'xsd:string'},...
                    'nfo:belongsToContainer',{fsdir, 'nfo:Folder'},...                    
                    });
                
                obj.IDs{1} = struct('id','idaaWorkflow');
                idResults = obj.IDs{1}.id;
                obj.pp.entity(idResults,{...
                    'prov:type','prov:Bundle',...
                    'prov:label','aa Workflow',...
                    'aa:objectModel','aa:aaWorkflow',...
                    'aa:version',{obj.version,'xsd:string'},...
                    });
                obj.pp.wasGeneratedBy(idResults,'-',now);
                obj.pp.wasAssociatedWith(idResults,'idaa');
                                
                obj.p = eval(basename(obj.provlib));
            end
            
        end
        
        function serialise(obj)
            if obj.isvalid
                obj.pp.bundle(obj.IDs{1}.id,obj.p);
                serialize(obj.pp,fullfile(obj.studypath,'aa_prov_workflow.provn'));
                serialize(obj.pp,fullfile(obj.studypath,'aa_prov_workflow.ttl'));
%                 serialize(obj.pp,fullfile(obj.studypath,'aa_prov_workflow.json'));
                serialize(obj.pp,fullfile(obj.studypath,'aa_prov_workflow.pdf'));
            end
        end
        
        function id = addModule(obj,stageindex)
            
            % Activity
            if isstruct(stageindex) % Remote
                [tag, ind] = strtok_ptrn(stageindex.stagetag,'_0');
                name = ['Remote ' stageindex.host '_' tag];
                index = sscanf(ind,'_%d');
                raap = load(stageindex.aapfilename); raap = raap.aap;
                
                iname = cell_index({raap.tasklist.main.module.name},tag);
                iindex = cell2mat({raap.tasklist.main.module(iname).index}) == index;
                rstageindex = iname(iindex);
                
                idname = ['idRemoteActivity_' tag];
                idattr = {...
                    'aap',aas_setcurrenttask(raap,rstageindex),...
                    'Location',[stageindex.host fullfile(fileparts(stageindex.aapfilename),tag)],...
                    };
                
                checkinput = false; % do not check input
            else
                smod = obj.aap.tasklist.main.module(stageindex);
                name = smod.name;
                index = smod.index;
                
                idname = ['idActivity_' name];
                idattr = {...
                    'aap',aas_setcurrenttask(obj.aap,stageindex),...
                    'Location',fullfile([obj.studypath smod.extraparameters.aap.directory_conventions.analysisid_suffix],name),...
                    };
                
                checkinput = true;
            end
            idattr = [idattr,...
                'Stagename',name,...
                'Index',index,...
                ];
            [prid_module, id] = obj.Module(idname,idattr);
            
            % Input(s)
            if checkinput
                [inputs, inputattrs] = aas_getstreams(obj.IDs{id}.aap,'in');
                for i = 1:numel(inputs)
                    istream = inputs{i};
                    if any(istream=='.')
                        [junk, istream] = strtok(istream,'.');
                        istream = istream(2:end);
                    end
                    isOptional = numel(inputattrs)>=i && isstruct(inputattrs{i}) && isfield(inputattrs{i},'isessential') && ~inputattrs{i}.isessential;
                    
                    % find source
                    if isfield(obj.dep.(sprintf('%s_%05d',name,index)),istream)
                        src = obj.dep.(sprintf('%s_%05d',name,index)).(istream);
                    else
                        if isOptional
                            continue;
                        else
                            aas_log(obj.aap,true,...
                                sprintf('Inputstream %s of module %s not found!',istream,sprintf('%s_%05d',name,index)));
                        end
                    end
                    if ~isempty(strfind(src,'Remote')) % remote src --> add
                        [junk,src] = strtok(src,':'); src = src(3:end);
                        rstage = smod.remotestream(strcmp({smod.remotestream.stream},istream));
                        idsrc = obj.addModule(rstage);
                    else % local --> already added
                        [lname, ind] = strtok_ptrn(src,'_0');
                        lindex = sscanf(ind,'_%d');
                        idattr = {...
                            'Stagename',lname,...
                            'Index',lindex,...
                            };
                        [junk, junk, idsrc] = obj.idExist(idattr);
                    end
                    
                    prid_inputstream = obj.addStream(idsrc,istream);
                    if isempty(prid_inputstream)
                        if isOptional, continue; 
                        else
                            aas_log(obj.aap,true,...
                                sprintf('Inputstream %s of module %s generated by %s not found!',istream,...
                                sprintf('%s_%05d',name,index),...
                                obj.IDs{idsrc}.aap.tasklist.currenttask.name));                            
                        end
                    end
                    if ~any(strcmp(obj.relations,[prid_inputstream,prid_module]))
                        obj.p.used(prid_module,prid_inputstream);
                        obj.relations{end+1} = [prid_inputstream,prid_module];
                    end
                end
            end
            
            % Output
            for o = aas_getstreams(obj.IDs{id}.aap,'out')
                ostream = o{1};
                
                prid_outputstream = obj.addStream(id,ostream);
                
                if ~isempty(prid_outputstream) &&... % optional outputs
                        ~any(strcmp(obj.relations,[prid_module,prid_outputstream]))
                    obj.p.wasGeneratedBy(prid_outputstream,prid_module)
                    obj.relations{end+1} = [prid_module,prid_outputstream];
                end
            end
            
        end
        
        function [prid, id] = addStream(obj,idsrc,stream)
            try
                [files, MD5, fname] = aas_getfiles_bystream_multilevel(obj.IDs{idsrc}.aap,...
                    1,1,stream,'output'); % TODO: associate files
            catch
                aas_log(obj.aap,false,sprintf('Outputstream %s of module %s not found!',stream,obj.IDs{idsrc}.aap.tasklist.currenttask.name));
                prid = ''; id = 0;
                return
            end
            
            [junk, MD5] = strtok(MD5); MD5 = MD5(2:end);
            
            idname = ['id' stream];
            idattr = {...
                'streamname',stream,...
                'filename',fname,...
                'hash',MD5,...
                };
            [prid, id] = obj.Stream(idname,idattr);
        end
        
        function [prid id] = Module(obj,idname,attr) % 'Location', 'Stagename','Index'
            [prid, num, id]= obj.idExist(idname,attr);
            if isempty(prid)
                obj.IDs{end+1} = struct('id', [idname num2str(num+1)]);
                for f = 1:numel(attr)/2
                    obj.IDs{end}.(attr{f*2-1}) = attr{f*2};
                end
                id = numel(obj.IDs);
                
                obj.p.activity(obj.IDs{id}.id,{...
                    'prov:type','aa:module',...
                    'prov:label',obj.IDs{id}.Stagename,...
                    'nfo:belongsToContainer',{obj.IDs{id}.Location, 'nfo:Folder'},...
                    });
                prid = obj.IDs{id}.id;
            end
        end
        
        function [prid id] = Stream(obj,idname,attr) % 'streamname','filename(full)','hash';
            [prid, num, id]= obj.idExist(idname,attr);
            if isempty(prid)
                obj.IDs{end+1} = struct('id', [idname num2str(num+1)]);
                for f = 1:numel(attr)/2
                    obj.IDs{end}.(attr{f*2-1}) = attr{f*2};
                end
                id = numel(obj.IDs);
                prid = obj.IDs{id}.id;
                
                % add hash
                [junk, hnum]= obj.idExist('idHash');
                obj.IDs{end+1} = struct(...
                    'id',['idHash' num2str(hnum+1)],...
                    'hash',obj.IDs{id}.hash ...
                    );
                obj.p.entity(obj.IDs{end}.id,{...
                    'prov:type','nfo:FileHash',...
                    'nfo:hashValue',obj.IDs{end}.hash,...
                    });
                
                obj.p.entity(obj.IDs{id}.id,{...
                    'prov:type','aa:stream',...
                    'prov:label',obj.IDs{id}.streamname,...
                    'nfo:fileUrl',url(obj.IDs{id}.filename),...
                    'nfo:fileName',{spm_file(obj.IDs{id}.filename,'filename'),'xsd:string'},...
                    'nfo:hasHash',obj.IDs{end}.id,...
                    });
            end
        end
        
        function [prid, num, id] = idExist(obj,varargin)
            prid = '';
            num = 0;
            id = 0;
            
            idname = '';
            idfields = [];
            switch nargin
                case 3
                    idname = varargin{1};
                    idfields = varargin{2};
                case 2
                    if ischar(varargin{1}), idname = varargin{1};
                    elseif iscell(varargin{1}), idfields = varargin{1};
                    end
            end
            
            ind = [];
            if ~isempty(idname)
                for i = 1:numel(obj.IDs)
                    if ~isempty(strfind(obj.IDs{i}.id,idname))
                        ind(end+1) = i;
                    end
                end
                num = numel(ind);
            else
                ind = 1:numel(obj.IDs);
            end
            
            for i = ind
                match = true;
                for f = 1:numel(idfields)/2
                    match = match && (isfield(obj.IDs{i},idfields{f*2-1}) && ...
                        (...
                        (strcmp(idfields{f*2-1},'aap')) ||... % skip aap
                        (ischar(idfields{f*2}) && strcmp(obj.IDs{i}.(idfields{f*2-1}),idfields{f*2})) ||...
                        (isnumeric(idfields{f*2}) && (obj.IDs{i}.(idfields{f*2-1}) == idfields{f*2})) ...                        
                        ));
                end
                if match
                    prid = obj.IDs{i}.id;
                    id = i;
                    break;
                end
            end
        end
    end
end

%% Utils

function u = url(fname)
%-File URL scheme
if ispc, s='/'; else s=''; end
u = ['file://' s strrep(fname,'\','/')];
e = ' ';
for i=1:length(e)
    u = strrep(u,e(i),['%' dec2hex(e(i))]);
end
% u = ['file://./' spm_file(u,'filename')];
end