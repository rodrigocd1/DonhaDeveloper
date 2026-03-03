public class WrapperClass 
{
        public List<SelectOption> listaCamposConta{get;set;}
        public List<SelectOption> listaFiltros{get;set;}
        public String campo1 { get; set; }
        public String criterio1 { get; set; }
        public String valor1 { get; set; }
        public String criterioDeFiltro { get; set; }
        public String orderBy { get; set; } 
        public String query{get;set;}
        public String condicaoQuery{get;set;}
        public String accinp { get; set; }   
    public list<account> accs = new list<account>();
    public list<account> listaAccs = new list<account>();
    public list<AccountWrapper> accwrap{get; set;}
    public list<account> selectedaccount{get; set;}
    public account anacc{get; set;}
    
        public void Changetype()
        {
        for(account ac:selectedaccount)
        {
                ac.type=anacc.type;             
        }                
        
        if( anacc.Price__c < 400 )
        {
                update selectedaccount;
        }
        else
        {
                        apexpages.addmessage(new apexpages.message(apexpages.severity.error,'This is only applicable for Price less than 400…..'));
        }
    }
    
        public WrapperClass()
        { 
                carregarCriteriosDeFiltros();
                carregarListaCamposConta();                             
                
                accwrap=  new list<accountwrapper>();
                anacc= new account();
                
                query = 'select name, Ownerid, Website, Type,Price__c from account ';
                        
                
    }
    
    public void pesquisar()
    {
        try
        {
                        accwrap=  new list<accountwrapper>();
                        anacc= new account();
                        
                        //condicaoQuery  = ' where website!= null ';
                        
                        if( (campo1 != '') && (criterio1 != '--Nenhum--') && (valor1 != '') )
                        {
                                condicaoQuery += ' AND ' + campo1 + ' Like ' + '\'%' +valor1 + '%\' '  ;
                        }
                                        
                        orderBy = ' order by Name asc';
                                        
                        accs = Database.query(query + condicaoQuery + orderBy); 
                        
                        accountWrapperObject();
        }
        catch(Exception e)
        {
                OzVisualForceMensagens.exibirMensagemAviso(query + condicaoQuery + orderBy);
        }
    
    }
    
    public void orderByName()
    {
        carregarListaRegistros('Name');    
    }
    
    public void orderByType()
    {
        carregarListaRegistros('Type');    
    }
    
    public void orderByWebsite()
    {
        carregarListaRegistros('Website');    
    }
    
    public void carregarListaRegistros(String CampoOrdenacao)
        {
                orderBy = CampoOrdenacao;
                
                accs.clear();
                                        
                Orderby  = ' order by ' + orderBy  + '  asc ';
                                
                accs = Database.query( query + condicaoQuery + orderBy );
                
                                                
                accwrap.clear();
                
                for(account a: accs)
        {
                        accountwrapper aw = new accountwrapper(a);                      
                        accwrap.add(aw);
        }               
                
        }  
    
    
     
    public void accountWrapperObject()
    {
      for(account a:accs)
      {
                accountwrapper aw = new accountwrapper(a);
                accwrap.add(aw);
      }
    }
    
    
       
    public void getselected()
    {
                selectedaccount = new list<account>();
                selectedaccount.clear();
        for(accountwrapper awrap: accwrap)
        {
                if(awrap.selected==true)
                {
                                selectedaccount.add(awrap.acc);
                }
        }
    }
    
    
    public void carregarListaCamposConta()
    {
        listaCamposConta = new List<SelectOption>();
        listaCamposConta = OzVisualForce.AdicionarItemEmOptionList( listaCamposConta , ' ');            
        listaCamposConta = OzVisualForce.AdicionarItemEmOptionList( listaCamposConta , 'Name');
        listaCamposConta = OzVisualForce.AdicionarItemEmOptionList( listaCamposConta , 'Type');
     
    }
    
    public void carregarCriteriosDeFiltros()
    {
        listaFiltros = new List<SelectOption>();
        listaFiltros = OzVisualForce.AdicionarItemEmOptionList( listaFiltros , '-- Nenhum --');
        listaFiltros = OzVisualForce.AdicionarItemEmOptionList( listaFiltros , 'Contém');
     
    }
    
}