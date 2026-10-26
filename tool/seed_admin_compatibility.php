<?php

declare(strict_types=1);

use Doctrine\DBAL\Connection;
use Providentia\Administration\Application\OperatorInventoryService;
use Providentia\Identity\Application\AuthenticationService;
use Providentia\Inventory\Application\InventoryService;
use Providentia\SharedKernel\Application\UuidGenerator;

// Disposable test databases and synthetic identities only. The backend fixture
// refuses a nonempty account database and issues real native bearer sessions.
$pairedBackend = $argv[1] ?? '';
$pairedFixturePath = $argv[2] ?? '';
if (getenv('APP_ENV') !== 'test' || getenv('PROVIDENTIA_STEP2_CONFORMANCE') !== '1'
    || !is_file($pairedBackend . '/tests/fixtures/runtime-response-http.php')
    || $pairedFixturePath === '') {
    throw new RuntimeException('An isolated paired backend and fixture path are required.');
}
$argv = [__FILE__, $pairedFixturePath];
$_SERVER['argv'] = $argv;
require $pairedBackend . '/tests/fixtures/runtime-response-http.php';
$pairedContainer = require $pairedBackend . '/config/container.php';
$pairedDb = $pairedContainer->get(Connection::class);
$pairedAuthentication = $pairedContainer->get(AuthenticationService::class);
$pairedIds = $pairedContainer->get(UuidGenerator::class);
$pairedInventory = $pairedContainer->get(OperatorInventoryService::class);
$pairedStock = $pairedContainer->get(InventoryService::class);
$pairedFixture = json_decode((string) file_get_contents($pairedFixturePath), true, 512, JSON_THROW_ON_ERROR);
$pairedActor = $pairedAuthentication->authenticate($pairedFixture['sessions']['alice']['accessToken']);
$pairedNow = (new DateTimeImmutable('now', new DateTimeZone('UTC')))->format('Y-m-d H:i:s');
$pairedDb->insert('administrator_requests', [
    'user_id' => $pairedFixture['sessions']['bob']['userId'],
    'status' => 'pending', 'reviewer_user_id' => null,
    'created_at' => $pairedNow, 'updated_at' => $pairedNow, 'revision' => 1,
]);
$pairedHome = $pairedFixture['homeId'];
$pairedLocalCategory = $pairedIds->generate();
$pairedLinked = $pairedIds->generate();
$pairedPrivate = $pairedIds->generate();
$pairedInventory->createCategory($pairedActor, $pairedHome, [
    'id' => $pairedLocalCategory, 'name' => 'Synthetic local pantry',
    'reason' => 'Paired Admin compatibility fixture', 'expectedRevision' => 0,
]);
$pairedInventory->createProduct($pairedActor, $pairedHome, [
    'id' => $pairedLinked, 'productId' => $pairedFixture['catalog']['pack']['productId'],
    'packId' => $pairedFixture['catalog']['pack']['packId'], 'unit' => 'kg',
    'reason' => 'Paired Admin compatibility fixture', 'expectedRevision' => 0,
]);
$pairedInventory->createProduct($pairedActor, $pairedHome, [
    'id' => $pairedPrivate, 'privateName' => 'Synthetic private stock', 'unit' => 'g',
    'reason' => 'Paired Admin compatibility fixture', 'expectedRevision' => 0,
]);
$pairedStock->manualAdjustment(
    $pairedActor, $pairedHome, $pairedLinked, '-0.125',
    'Synthetic signed fractional stock', 'paired-admin-linked-stock',
);
$pairedStock->manualAdjustment(
    $pairedActor, $pairedHome, $pairedPrivate, '0.25',
    'Synthetic stock before zero count', 'paired-admin-private-stock',
);
$pairedStock->manualAdjustment(
    $pairedActor, $pairedHome, $pairedPrivate, '-0.25',
    'Synthetic zero stock', 'paired-admin-private-zero-stock',
);
$pairedFixture['adminCompatibility'] = [
    'administratorRequestRevision' => 1,
    'linkedId' => $pairedLinked,
    'privateId' => $pairedPrivate,
    'localCategoryId' => $pairedLocalCategory,
    'globalCategoryId' => $pairedDb->fetchOne('SELECT category_id FROM products WHERE id = ?', [
        $pairedFixture['catalog']['pack']['productId'],
    ]),
    'canonicalName' => $pairedFixture['catalog']['pack']['name'],
    'canonicalPack' => '2 kg',
];
if (file_put_contents($pairedFixturePath, json_encode($pairedFixture, JSON_THROW_ON_ERROR)) === false) {
    throw new RuntimeException('Unable to persist the ephemeral Admin fixture.');
}
chmod($pairedFixturePath, 0600);
