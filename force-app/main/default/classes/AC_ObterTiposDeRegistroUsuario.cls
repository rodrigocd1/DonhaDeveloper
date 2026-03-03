public class AC_ObterTiposDeRegistroUsuario 
{
    public static List<String> GetAvailableRecordTypeNamesForSObject(Schema.SObjectType objType) 
    {
        List<String> names = new List<String>();
        List<RecordTypeInfo> infos = objType.getDescribe().getRecordTypeInfos();
        // If there are 2 or more RecordTypes...
        if (infos.size() > 1) 
        {
            for (RecordTypeInfo i : infos) 
            {
               if (i.isAvailable() 
               // Ignore the Master Record Type, whose Id always ends with 'AAA'.
               // We check the Id because Name can change depending on the user's language.
                && !String.valueOf(i.getRecordTypeId()).endsWith('AAA'))
                    names.add(i.getName() + ',' + i.getRecordTypeId());
            }
        } 
        // Otherwise there's just the Master record type,
        // so add it in, since it MUST always be available
        else names.add(infos[0].getName());
        return names;
    }
    
    // List<String> availableCaseTypes =  AC_ObterTiposDeRegistroUsuario.GetAvailableRecordTypeNamesForSObject(Case.SObjectType);

 	//System.debug(availableCaseTypes);
 // returns ('Web Team')
    

}