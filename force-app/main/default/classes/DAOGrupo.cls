/**********************************************************************************************************************************************************************
    @description Classe de métodos de persistência do objeto Grupo.
    @author Avanxo - Matheus Martins
    @date 18/06/14
**********************************************************************************************************************************************************************/
public with sharing class DAOGrupo {
    /** 
        @description Metodo para obter todos os grupos de acordo com o filtro do parametro
        @param filtro String que ira filtrar os resultados
        @return listaGrupo Lista com todos os grupos filtrados
        @author Avanxo - Matheus Martins
        @date 18/06/14
    */
    public static List<Group> obterTodosGruposFiltradoPorStringParametro( String filtro ){
        List<Group> listaGrupo = null;
        try{
            listaGrupo = [ SELECT Id, Name FROM Group WHERE Name like: filtro order by Name];
            return listaGrupo;
        }catch( Exception e ){
            throw new DAOException('Erro ao obter todos grupos filtrado por String: '+ e, 'DAOGrupo', 'obterTodosGruposFiltradoPorStringParametro');
        }
    }
    
    /** 
        @description Metodo para obter todos os grupos e ser consumido depois
        @return Map<Id,Group> Mapa Id e grupo
        @author Avanxo - Matheus Martins
        @date 18/06/14
    */
    public static Map<Id,Group> obterGrupoComDetalhesComRelated(){
        try{
            Map<Id,Group> mapaIdGrupo = new Map<Id,Group>([SELECT Id, RelatedId, Type FROM Group WHERE RelatedId != null]);
            return mapaIdGrupo;
            
        }catch( Exception e ){
            return null;
        }
    }
}