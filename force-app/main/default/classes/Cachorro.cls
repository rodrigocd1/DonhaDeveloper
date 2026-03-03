// Subclasse concreta Cachorro que estende a classe Animal
public class Cachorro extends Animal {
    public Cachorro(String nome) {
        super(nome);
    }
    
    // Implementação do método fazerSom para Cachorro
    public override void fazerSom() {
        System.debug(nome + ' faz latidos.');
    }
}