public class CodeCoverageController {

    public String messageUnder10 {
        get { return CodeCoverageHelper.MESSAGE_UNDER_10; }
        private set;
    }
    public list< String > listaItensPackage = new list< String >();
    public String packageXML {get;set;}

    public String messageUnder75 {
        get { return CodeCoverageHelper.MESSAGE_UNDER_75; }
        private set;
    } 

    public String messageAbove75 {
        get { return CodeCoverageHelper.MESSAGE_ABOVE_75; }
        private set;
    }  
    
    public String[] codeCoverageMessages {
        get {
            if(codeCoverageMessages == null) codeCoverageMessages = new String[]{};
            return codeCoverageMessages;
        }
        set;
    }

    public Map<String, Decimal> codeCoverageMap {
        get {
            if(codeCoverageMap == null || codeCoverageMap.isEmpty()) {
                codeCoverageMap = CodeCoverageHelper.getCodeCoverage();
            }
            return codeCoverageMap;                
        }

        set;
    }

    public CodeCoverageController() {
        populateCodeCoverageByCoverage();
    }

    public void populateCodeCoverageByName() {
        Map<String, Decimal> coverageMap = codeCoverageMap;
        populateCodeCoverageInfo(coverageMap);

    }

    public void populateCodeCoverageByCoverage() {
        Map<String, Decimal> coverageMap = CodeCoverageHelper.sortCodeCoverageMapByCoverage(codeCoverageMap);
        populateCodeCoverageInfo(coverageMap);
    }

    public void populateCodeCoverageInfo(Map<String, Decimal> coverageMap){
        codeCoverageMessages.clear();
        if( ! String.isBlank( packageXML ) && ! String.isEmpty( packageXML ) )
        {
            packageXML = packageXML.replaceAll(' ', '');
            packageXML = packageXML.replaceAll('<members>', '');
            packageXML = packageXML.replaceAll('</members>', '');
            
            if( packageXML.contains('\n') )
            {    
        		listaItensPackage = packageXML.split('\n');    
            }
            else if( packageXML.length() > 1 )
            {
                listaItensPackage.add( packageXML );
            }
            else
            {
                packageXML = '';
            }
        }
        
   
        for(String className : coverageMap.keySet()) {
            
            if( !listaItensPackage.contains(className) && !listaItensPackage.isEmpty() )
            {
                continue;
            }
            
            Decimal coverage = coverageMap.get(className);
            coverage = coverage.setScale(2);

            String coverageMessage = '';
            
            try
            {
                coverageMessage = CodeCoverageHelper.buildCodeCoverageMessage(coverage, className);
            }
            catch( Exception e )
            {
                
            }
            
            codeCoverageMessages.add(coverageMessage);
        }
    }

}