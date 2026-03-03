/**
 * Classe Validador fornece métodos estáticos para validar se os valores fornecidos são nulos ou considerados "brancos",
 * como strings em branco, ou coleções sem elementos.
 */
public class Validador {

    /**
     * Verifica se uma String é nula ou em branco.
     * 
     * @param valor A string a ser validada.
     * @return Boolean Retorna verdadeiro se o valor é nulo ou em branco, falso caso contrário.
     */
    public static Boolean validarNuloOuBranco(String valor) {
        return valor == null || valor == '';
    }
    
    /**
     * Verifica se um Integer é nulo.
     * 
     * @param valor O Integer a ser validado.
     * @return Boolean Retorna verdadeiro se o valor é nulo, falso caso contrário.
     */
    public static Boolean validarNuloOuBranco(Integer valor) {
        return valor == null;
    }
    
    /**
     * Verifica se um Decimal é nulo.
     * 
     * @param valor O Decimal a ser validado.
     * @return Boolean Retorna verdadeiro se o valor é nulo, falso caso contrário.
     */
    public static Boolean validarNuloOuBranco(Decimal valor) {
        return valor == null;
    }
    
    /**
     * Verifica se um SObject é nulo.
     * 
     * @param valor O SObject a ser validado.
     * @return Boolean Retorna verdadeiro se o valor é nulo, falso caso contrário.
     */
    public static Boolean validarNuloOuBranco(SObject valor) {
        return valor == null;
    }
    
    /**
     * Verifica se uma List é nula ou vazia.
     * 
     * @param valor A List a ser validada.
     * @return Boolean Retorna verdadeiro se a lista é nula ou vazia, falso caso contrário.
     */
    public static Boolean validarNuloOuBranco(List<Object> valor) {
        return valor == null || valor.isEmpty();
    }
    
    /**
     * Verifica se um Date é nulo.
     * 
     * @param valor O Date a ser validado.
     * @return Boolean Retorna verdadeiro se o valor é nulo, falso caso contrário.
     */
    public static Boolean validarNuloOuBranco(Date valor) {
        return valor == null;
    }
    
    /**
     * Verifica se um DateTime é nulo.
     * 
     * @param valor O DateTime a ser validado.
     * @return Boolean Retorna verdadeiro se o valor é nulo, falso caso contrário.
     */
    public static Boolean validarNuloOuBranco(DateTime valor) {
        return valor == null;
    }
    
    /**
     * Verifica se um Set é nulo ou vazio.
     * 
     * @param valor O Set a ser validado.
     * @return Boolean Retorna verdadeiro se o set é nulo ou vazio, falso caso contrário.
     */
    public static Boolean validarNuloOuBranco(Set<Object> valor) {
        return valor == null || valor.isEmpty();
    }
    
    /**
     * Verifica se um Map é nulo ou vazio.
     * 
     * @param valor O Map a ser validado.
     * @return Boolean Retorna verdadeiro se o map é nulo ou vazio, falso caso contrário.
     */
    public static Boolean validarNuloOuBranco(Map<Object, Object> valor) {
        return valor == null || valor.isEmpty();
    }
    
    // Adicione mais sobrecargas conforme necessário para outros tipos...
}