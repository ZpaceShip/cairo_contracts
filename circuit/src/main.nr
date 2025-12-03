fn main(secret_word: Field, answer_hash: pub Field) {

    let hash1 = std::hash::pedersen_hash([secret_word]);

    assert(hash1 == answer_hash);
}


#[test]
fn test_main() {
    let secret_word = 0x550;
    let answer_hash = std::hash::pedersen_hash([secret_word]);
    main(secret_word, answer_hash);
}

